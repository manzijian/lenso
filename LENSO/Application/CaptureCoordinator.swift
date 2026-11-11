import AppKit
import CoreGraphics
import OSLog
import SwiftUI

extension Notification.Name {
    static let screenshotSaved = Notification.Name("com.lenso.screenshotSaved")
    /// 截图后显示预览：保存完成后发给菜单栏面板，打开预览窗口
    static let openPreviewForScreenshot = Notification.Name("com.lenso.openPreviewForScreenshot")
    /// 编辑器滚轮事件通知
    static let editorScrollWheel = Notification.Name("com.lenso.editorScrollWheel")
    /// 编辑器鼠标右键事件通知
    static let editorRightClick = Notification.Name("com.lenso.editorRightClick")
}

private let log = Logger(subsystem: "com.lenso.app", category: "capture")

/// 截图流程编排（规范 6.1）：
/// 权限 → 选区 → 抓帧 → 编辑覆盖层（保存/复制/置顶/OCR/丢弃）→ 按动作落盘
@MainActor
final class CaptureCoordinator: NSObject {
    static let shared = CaptureCoordinator()

    private let capture = ScreenCaptureService()
    private var selector: RegionSelectorController?
    private var editorPanel: NSPanel?
    private var editorHost: NSHostingView<CaptureEditorView>?
    /// 钉图控制器集合（持有引用防止释放）
    private var pinnedControllers: [PinnedScreenshotController] = []

    func startRegionCapture() {
        log.info("startRegionCapture triggered")
        // 已经有一轮选区在进行：先把它收掉再重开，而不是默默不理
        // （用户按了热键却什么都没发生，会以为应用卡住了）
        if let selector {
            log.info("selector already open, restarting")
            selector.cancel()
            self.selector = nil
        }
        Task { await startRegionCaptureAsync() }
    }

    private func startRegionCaptureAsync() async {
        // 触发阶段**不再**做权限探测。
        //
        // 以前这里会先枚举 SCShareableContent 当作权限检查，问题有两个：
        //   1. 枚举本身会偶发失败（锁屏、显示器热插拔、系统繁忙都会），
        //      一失败就直接 return，用户看到的就是「按了热键没反应」；
        //   2. 选区浮层根本不需要屏幕录制权限——它只是个透明面板。
        // 所以现在先无条件把选区上屏，真正抓图时若没权限，在「确认」那一步
        // 给出明确提示（见下面的 catch）。触发因此永远是即时的。

        // 丝滑 v2：面板立刻上屏（不预抓图），选区里透出实时桌面。
        // 确认后才抓一张全屏当编辑器背景，抓时把选区面板排除在外。
        let selector = RegionSelectorController()
        self.selector = selector
        let captureService = capture
        selector.begin { [weak self, weak selector] rect, displayID, panelWindowNumber, prefrozen in
            Task { @MainActor in
                guard let self, let selector, !selector.isDismissed else { return }
                do {
                    // 优先用选区阶段就已经冻结好的画面：编辑器可以立刻上屏。
                    // 只有冻结帧还没到位（热键按下后不到 ~200ms 就确认）才现场抓。
                    let frozen: CGImage
                    if let prefrozen {
                        frozen = prefrozen
                    } else {
                        frozen = try await captureService.captureDisplayExcluding(
                            displayID: displayID, excludedWindowIDs: [panelWindowNumber]
                        )
                    }
                    let screenFrame = NSScreen.screens
                        .first(where: {
                            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
                                || ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
                        })?
                        .frame ?? rect
                    self.showFullEditor(frozen: frozen, screenFrame: screenFrame, initialSelection: rect)
                    selector.dismiss()
                    self.selector = nil
                } catch {
                    NSSound.beep()
                    log.error("capture failed: \(error.localizedDescription, privacy: .public)")
                    if Self.isPermissionError(error) {
                        self.presentCaptureError(
                            title: "无法截图：缺少屏幕录制权限",
                            message: "请到「系统设置 → 隐私与安全性 → 屏幕录制」中为 lenso 开启权限，然后重新截图。",
                            isPermission: true
                        )
                    } else {
                        self.presentCaptureError(title: "截图失败", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func showFullEditor(
        frozen: CGImage,
        screenFrame: CGRect,
        initialSelection: CGRect
    ) {
        let coordinator = self
        let editorView = CaptureEditorView(
            frozenImage: frozen,
            screenFrame: screenFrame,
            initialSelection: initialSelection,
            onComplete: { [weak coordinator] finalImage in
                coordinator?.closeEditor()
                coordinator?.handleFinish(finalImage: finalImage)
            },
            onQuickCopy: { [weak coordinator] image in
                coordinator?.copyToClipboard(image: image)
                // 只复制不保存：提示必须是“已复制到剪贴板”，不许写“截图已保存”
                if AppSettings.shared.showFloatingPreview {
                    SaveToastController.shared.show(
                        title: "已复制到剪贴板", subtitle: "未保存到图库", thumbnail: image
                    )
                }
            },
            onPin: { [weak coordinator] image, rect in
                coordinator?.closeEditor()
                coordinator?.pin(image: image, initialFrame: rect)
            }
        )
        let hosting = NSHostingView(rootView: editorView)
        hosting.appearance = NSAppearance(named: .aqua) // 编辑器浅色玻璃
        editorHost = hosting

        let panel = EditorPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hosting
        panel.setFrame(screenFrame, display: true)
        panel.onCancel = { [weak self] in
            self?.closeEditor()
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        editorPanel = panel
        log.info("full editor shown on display \(NSStringFromRect(panel.screen?.frame ?? .zero), privacy: .public)")
    }

    private func closeEditor() {
        editorPanel?.orderOut(nil)
        editorPanel?.close()
        editorPanel = nil
        editorHost = nil
    }

    private func handleFinish(finalImage: CGImage?) {
        guard let image = finalImage else {
            log.info("editor discarded")
            return
        }
        do {
            let record = try ScreenshotStore.shared.save(image: image, capturedAt: Date())
            if AppSettings.shared.autoCopyAfterCapture {
                copyToClipboard(image: image)
            }
            NotificationCenter.default.post(name: .screenshotSaved, object: record)
            if AppSettings.shared.showFloatingPreview {
                SaveToastController.shared.show(thumbnail: try? ScreenshotStore.shared.loadThumbnail(record))
            }
            if AppSettings.shared.showPreviewAfterCapture {
                NotificationCenter.default.post(name: .openPreviewForScreenshot, object: record.id)
            }
            NSSound.beep()
            log.info("saved \(record.filename, privacy: .public)")
        } catch {
            NSSound.beep()
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 钉图：浮在所有窗口之上的可拖动图片窗
    private func pin(image: CGImage, initialFrame: NSRect? = nil) {
        let controller = PinnedScreenshotController(image: image, initialFrame: initialFrame, coordinator: self)
        pinnedControllers.append(controller)
        log.info("pinned screenshot controller created, total active: \(self.pinnedControllers.count)")
    }

    func removePinnedController(_ controller: PinnedScreenshotController) {
        pinnedControllers.removeAll { $0 === controller }
    }

    /// SCK 在没有屏幕录制权限时抛的错误（域 SCStreamErrorDomain / 用户取消）。
    private static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "SCStreamErrorDomain" { return true }
        // CGError 里 .notPermitted / .invalidDisplay 也常被包成这个
        return ns.code == -3801 || ns.code == -3802
    }

    /// 截图失败时给一个用户看得见的提示（beep 太容易错过）。
    /// 用 NSAlert 而不是自绘浮层：失败路径要尽量简单，别再依赖别的东西能跑起来。
    private func presentCaptureError(title: String, message: String, isPermission: Bool = false) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        if isPermission {
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "好")
        } else {
            alert.addButton(withTitle: "好")
        }
        let response = alert.runModal()
        if isPermission && response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func copyToClipboard(image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}

/// 编辑器覆盖面板：Esc 取消，滚轮缩放选区，右键取消/退回上一级
final class EditorPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func scrollWheel(with event: NSEvent) {
        NotificationCenter.default.post(name: .editorScrollWheel, object: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .editorRightClick, object: event)
    }
}

// MARK: - 贴图控制器与独立浮动工具栏（专属针对贴图操作，不遮挡屏幕也不进入二次截图）

@MainActor
final class PinnedScreenshotController: NSObject {
    weak var coordinator: CaptureCoordinator?
    let panel: NSPanel
    let toolbarPanel: NSPanel
    let imageView: PinnedImageView
    let state = AnnotationState()
    private var isToolbarVisible = false

    init(image: CGImage, initialFrame: NSRect?, coordinator: CaptureCoordinator) {
        self.coordinator = coordinator

        let size: NSSize
        let origin: NSPoint

        if let initialFrame {
            size = initialFrame.size
            origin = initialFrame.origin
        } else {
            let maxWidth: CGFloat = 520
            let scale = min(1, maxWidth / CGFloat(image.width))
            size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            if let screen = NSScreen.main {
                origin = NSPoint(
                    x: screen.frame.midX - size.width / 2,
                    y: screen.frame.midY - size.height / 2
                )
            } else {
                origin = .zero
            }
        }

        // 主贴图浮窗
        panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        // 工具栏卫星浮窗（跟随主贴图）
        toolbarPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toolbarPanel.level = .floating
        toolbarPanel.isOpaque = false
        toolbarPanel.backgroundColor = .clear
        toolbarPanel.hasShadow = false
        toolbarPanel.hidesOnDeactivate = false

        imageView = PinnedImageView(frame: NSRect(origin: .zero, size: size), image: image, state: state)
        super.init()

        imageView.onClose = { [weak self] in
            self?.close()
        }
        imageView.onToggleEditing = { [weak self] in
            self?.toggleToolbar()
        }
        imageView.onWindowMovedOrResized = { [weak self] in
            self?.updateToolbarPosition()
        }

        panel.contentView = imageView
        panel.setFrameOrigin(origin)

        // 配置工具栏视图
        let toolbarView = PinnedToolbarView(
            state: state,
            onUndo: { [weak self] in
                self?.state.undo()
                self?.imageView.needsDisplay = true
            },
            onRedo: { [weak self] in
                self?.state.redo()
                self?.imageView.needsDisplay = true
            },
            onOCR: { [weak self] in
                self?.runOCR()
            },
            onCopy: { [weak self] in
                self?.copyImage()
            },
            onSave: { [weak self] in
                self?.saveImage()
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
        let hosting = NSHostingView(rootView: toolbarView)
        hosting.appearance = NSAppearance(named: .aqua)
        toolbarPanel.contentView = hosting

        panel.orderFrontRegardless()
    }

    func toggleToolbar() {
        if isToolbarVisible {
            hideToolbar()
        } else {
            showToolbar()
        }
    }

    func showToolbar() {
        guard !isToolbarVisible else { return }
        isToolbarVisible = true
        updateToolbarPosition()
        if toolbarPanel.parent != panel {
            panel.addChildWindow(toolbarPanel, ordered: .above)
        }
        toolbarPanel.orderFront(nil)
    }

    func hideToolbar() {
        guard isToolbarVisible else { return }
        isToolbarVisible = false
        state.activeKind = nil
        toolbarPanel.orderOut(nil)
        panel.removeChildWindow(toolbarPanel)
        panel.invalidateCursorRects(for: imageView)
        imageView.needsDisplay = true
    }

    func updateToolbarPosition() {
        guard isToolbarVisible else { return }
        let pFrame = panel.frame
        let barWidth: CGFloat = 490
        let barHeight: CGFloat = 46
        let spacing: CGFloat = 8

        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 2560, height: 1440)

        var x = pFrame.midX - barWidth / 2
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - barWidth - 8))

        var y = pFrame.minY - barHeight - spacing
        if y < visibleFrame.minY + 8 {
            // 如果贴在屏幕底部，自动吸附到贴图上方
            y = pFrame.maxY + spacing
        }

        toolbarPanel.setFrame(NSRect(x: x, y: y, width: barWidth, height: barHeight), display: true)
    }

    func close() {
        hideToolbar()
        toolbarPanel.close()
        panel.orderOut(nil)
        panel.close()
        coordinator?.removePinnedController(self)
    }

    func copyImage() {
        let composited = imageView.renderCompositedImage()
        coordinator?.copyToClipboard(image: composited)
        if AppSettings.shared.showFloatingPreview {
            SaveToastController.shared.show(
                title: "已复制到剪贴板",
                subtitle: state.annotations.isEmpty ? "贴图原始图像" : "包含 \(state.annotations.count) 处标注",
                thumbnail: composited
            )
        }
    }

    func saveImage() {
        let composited = imageView.renderCompositedImage()
        do {
            let record = try ScreenshotStore.shared.save(image: composited, capturedAt: Date())
            if AppSettings.shared.autoCopyAfterCapture {
                coordinator?.copyToClipboard(image: composited)
            }
            NotificationCenter.default.post(name: .screenshotSaved, object: record)
            if AppSettings.shared.showFloatingPreview {
                SaveToastController.shared.show(thumbnail: try? ScreenshotStore.shared.loadThumbnail(record))
            }
            NSSound.beep()
        } catch {
            NSSound.beep()
        }
    }

    func runOCR() {
        let composited = imageView.renderCompositedImage()
        Task {
            do {
                let lines = try await ProviderRegistry.ocr.recognizeText(in: composited, languages: ["zh-Hans", "en-US"])
                let fullText = lines.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !fullText.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullText, forType: .string)
                    SaveToastController.shared.show(
                        title: "已识别并复制文字",
                        subtitle: String(fullText.prefix(35)) + (fullText.count > 35 ? "..." : ""),
                        thumbnail: composited
                    )
                } else {
                    SaveToastController.shared.show(
                        title: "未识别到文字",
                        subtitle: "请尝试放大贴图或更清晰的区域",
                        thumbnail: composited
                    )
                }
            } catch {
                SaveToastController.shared.show(
                    title: "文字识别失败",
                    subtitle: error.localizedDescription,
                    thumbnail: composited
                )
            }
        }
    }
}

// MARK: - 贴图工具栏视图（SwiftUI 高对比胶囊浮条）

private struct PinnedToolbarView: View {
    @Bindable var state: AnnotationState
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onOCR: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // 选择 / 移动工具
            Button {
                state.activeKind = nil
            } label: {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state.activeKind == nil ? .white : Color.primary.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(state.activeKind == nil ? Color(nsColor: .controlAccentColor) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .help("选择与移动 (V)")

            ForEach([AnnotationKind.rect, .ellipse, .arrow, .brush, .text, .mosaic, .highlight], id: \.self) { kind in
                Button {
                    state.activeKind = state.activeKind == kind ? nil : kind
                } label: {
                    Image(systemName: kind.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(state.activeKind == kind ? Color(nsColor: .controlAccentColor) : Color.primary.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(state.activeKind == kind ? Color(nsColor: .controlAccentColor).opacity(0.15) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(kind.label)
            }

            Divider().frame(height: 18)

            // 颜色选择菜单
            Menu {
                ForEach(0..<AnnotationPalette.count, id: \.self) { idx in
                    Button {
                        state.colorIndex = idx
                    } label: {
                        Text(colorName(for: idx))
                    }
                }
            } label: {
                Circle()
                    .fill(AnnotationPalette[state.colorIndex])
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26, height: 26)
            .help("标注颜色")

            Divider().frame(height: 18)

            // 撤销 / 重做
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(state.canUndo ? 0.85 : 0.35))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!state.canUndo)
            .help("撤销 (⌘Z)")

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(state.canRedo ? 0.85 : 0.35))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!state.canRedo)
            .help("重做 (⇧⌘Z)")

            Divider().frame(height: 18)

            // OCR
            Button(action: onOCR) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("识别文字 (OCR)")

            // 复制
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("复制到剪贴板 (⌘C)")

            // 保存
            Button(action: onSave) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("保存到历史记录 (⌘S)")

            // 关闭
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("关闭贴图")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
    }

    private func colorName(for index: Int) -> String {
        switch index {
        case 0: return "红色"
        case 1: return "橙色"
        case 2: return "黄色"
        case 3: return "蓝色"
        case 4: return "紫色"
        case 5: return "黑色"
        case 6: return "白色"
        default: return "颜色"
        }
    }
}

// MARK: - 贴图展示及标注交互视图

final class PinnedImageView: NSView, NSTextFieldDelegate {
    let image: CGImage
    let state: AnnotationState
    var onClose: (() -> Void)?
    var onToggleEditing: (() -> Void)?
    var onWindowMovedOrResized: (() -> Void)?

    private let closeButton = NSButton()
    private var tracking: NSTrackingArea?
    private let baseSize: NSSize
    private var currentScale: CGFloat = 1.0

    // 文字标注临时输入框
    private var activeTextField: NSTextField?
    private var textStartNormPoint: CGPoint?

    override var isFlipped: Bool { true }

    init(frame: NSRect, image: CGImage, state: AnnotationState) {
        self.image = image
        self.state = state
        self.baseSize = frame.size
        super.init(frame: frame)
        toolTip = "左键拖拽移动 · 滚轮缩放 · 右键/空格唤出编辑栏 · 双击关闭"

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        closeButton.bezelStyle = .circular
        closeButton.controlSize = .small
        closeButton.title = "✕"
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func closeClicked() { onClose?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 绘制原底图
        let nsImage = NSImage(cgImage: image, size: bounds.size)
        nsImage.draw(in: bounds)

        // 绘制所有标注及正在拉取的草稿
        var all = state.annotations
        if let draft = state.draft {
            all.append(draft)
        }
        for ann in all {
            AnnotationRenderer.drawSingleAnnotation(ann, in: ctx, size: bounds.size, baseImage: image, scale: 1.0)
        }
    }

    func renderCompositedImage() -> CGImage {
        AnnotationRenderer.renderAnnotations(state.annotations, onto: image)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !closeButton.isHidden {
            let ptInClose = closeButton.convert(point, from: self)
            if closeButton.bounds.contains(ptInClose) {
                return closeButton
            }
        }
        if let field = activeTextField {
            let ptInField = field.convert(point, from: self)
            if field.bounds.contains(ptInField) {
                return field
            }
        }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if state.activeKind != nil {
            addCursorRect(bounds, cursor: .crosshair)
        } else {
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if activeTextField != nil {
            commitTextEditing()
        }

        // 选择 / 移动模式：拖拽移动窗口
        if state.activeKind == nil {
            if event.clickCount == 2 {
                onClose?()
                return
            }
            window?.performDrag(with: event)
            onWindowMovedOrResized?()
            return
        }

        let pt = convert(event.locationInWindow, from: nil)
        let norm = CGPoint(
            x: min(max(pt.x / max(1, bounds.width), 0), 1),
            y: min(max(pt.y / max(1, bounds.height), 0), 1)
        )

        // 文字标注工具：点击位置弹出输入框
        if state.activeKind == .text {
            startTextEditing(at: pt, norm: norm)
            return
        }

        // 其它标注工具：开始绘制
        state.draft = Annotation(
            kind: state.activeKind!,
            start: norm,
            end: norm,
            colorIndex: state.colorIndex,
            strokeWidth: state.strokeWidth
        )
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var draft = state.draft else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let norm = CGPoint(
            x: min(max(pt.x / max(1, bounds.width), 0), 1),
            y: min(max(pt.y / max(1, bounds.height), 0), 1)
        )
        draft.end = norm
        state.draft = draft
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let draft = state.draft else { return }
        let dx = abs(draft.end.x - draft.start.x) * bounds.width
        let dy = abs(draft.end.y - draft.start.y) * bounds.height
        if dx > 4 || dy > 4 {
            state.push(draft)
        }
        state.draft = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if activeTextField != nil {
            cancelTextEditing()
            return
        }
        if state.draft != nil {
            state.draft = nil
            needsDisplay = true
            return
        }
        if state.activeKind != nil {
            state.activeKind = nil
            window?.invalidateCursorRects(for: self)
            return
        }
        // 选择模式下右键：呼出或关闭操作工具栏
        onToggleEditing?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            if activeTextField != nil {
                cancelTextEditing()
                return
            }
            if state.activeKind != nil {
                state.activeKind = nil
                window?.invalidateCursorRects(for: self)
                return
            }
            onToggleEditing?()
            return
        }
        if event.keyCode == 49 { // Space
            onToggleEditing?()
            return
        }
        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.05 else { return }

        let zoomFactor: CGFloat = delta > 0 ? 1.08 : 0.92
        let newScale = min(max(currentScale * zoomFactor, 0.15), 5.0)
        guard newScale != currentScale else { return }

        currentScale = newScale
        guard let window else { return }

        let mouseScreen = NSEvent.mouseLocation
        let oldFrame = window.frame
        let newWidth = max(40, round(baseSize.width * newScale))
        let newHeight = max(40, round(baseSize.height * newScale))

        let relX = (mouseScreen.x - oldFrame.minX) / max(1, oldFrame.width)
        let relY = (mouseScreen.y - oldFrame.minY) / max(1, oldFrame.height)

        let newX = mouseScreen.x - newWidth * relX
        let newY = mouseScreen.y - newHeight * relY
        let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)

        window.setFrame(newFrame, display: true)
        onWindowMovedOrResized?()
    }

    private func startTextEditing(at point: NSPoint, norm: CGPoint) {
        activeTextField?.removeFromSuperview()
        let field = NSTextField(frame: NSRect(x: max(8, point.x), y: max(8, point.y), width: 180, height: 26))
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9)
        field.textColor = AnnotationPaletteNS[state.colorIndex]
        field.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        field.focusRingType = .none
        field.delegate = self
        field.placeholderString = "输入文本并回车"
        addSubview(field)
        window?.makeFirstResponder(field)
        self.activeTextField = field
        self.textStartNormPoint = norm
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEditing()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextEditing()
            return true
        }
        return false
    }

    private func commitTextEditing() {
        guard let field = activeTextField, let start = textStartNormPoint else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)])
            let endNorm = CGPoint(
                x: min(1, start.x + size.width / max(1, bounds.width)),
                y: min(1, start.y + size.height / max(1, bounds.height))
            )
            var ann = Annotation(
                kind: .text,
                start: start,
                end: endNorm,
                colorIndex: state.colorIndex,
                strokeWidth: state.strokeWidth
            )
            ann.text = text
            state.push(ann)
        }
        field.removeFromSuperview()
        activeTextField = nil
        textStartNormPoint = nil
        needsDisplay = true
    }

    private func cancelTextEditing() {
        activeTextField?.removeFromSuperview()
        activeTextField = nil
        textStartNormPoint = nil
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        if state.activeKind == nil {
            closeButton.isHidden = false
        }
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }
}
