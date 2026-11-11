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

    private var previewController: PinnedScreenshotController?

    /// 钉图 / 浮动预览：浮在所有窗口之上的纯粹可拖动图片窗（无任何包裹窗体与黑边，回到刚截图的原汁原味）
    func pin(image: CGImage, initialFrame: NSRect? = nil, isPreview: Bool = false) {
        // 如果是图库预览，先彻底关闭已有的旧预览浮窗，杜绝连续双击产生多重相同窗口堆叠、导致“关闭一次关不掉”的问题
        if isPreview {
            if let existing = previewController {
                existing.close()
                previewController = nil
            }
        }
        let controller = PinnedScreenshotController(image: image, initialFrame: initialFrame, coordinator: self)
        if isPreview {
            previewController = controller
        }
        pinnedControllers.append(controller)
        log.info("pinned screenshot controller created, total active: \(self.pinnedControllers.count)")
    }

    func removePinnedController(_ controller: PinnedScreenshotController) {
        pinnedControllers.removeAll { $0 === controller }
        if previewController === controller {
            previewController = nil
        }
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

/// 贴图/预览浮动面板：支持 Esc、⌘W 一键彻底关闭，空格切换工具栏，响应键盘事件
final class PinnedPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onSpace: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc 键立即彻底关闭
            onCancel?()
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" { // ⌘W
            onCancel?()
            return
        }
        if event.keyCode == 49 { // 空格键切换底部编辑栏
            onSpace?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - 贴图控制器与独立浮动工具栏（专属针对贴图操作，不遮挡屏幕也不进入二次截图）

@Observable
final class PinnedEditorState {
    var isSidePanelVisible = false
    var panelTab: PanelTab = .ocr
    var ocrPhase: OCRPhase = .idle
    var ocrLines: [RecognizedText] = []
    var ocrErrorMessage: String? = nil
    var translationPhase: TranslationPhase = .idle
    var translations: [UUID: String] = [:]
    var translationErrorMessage: String? = nil
    var justSavedNote: Bool = false
    @ObservationIgnored var ocrTask: Task<Void, Never>?
    @ObservationIgnored var translationTask: Task<Void, Never>?
}

@MainActor
final class PinnedScreenshotController: NSObject {
    weak var coordinator: CaptureCoordinator?
    let panel: NSPanel
    let toolbarPanel: NSPanel
    let sidePanel: NSPanel
    let imageView: PinnedImageView
    let state = AnnotationState()
    let pinnedState = PinnedEditorState()
    private var isToolbarVisible = false

    init(image: CGImage, initialFrame: NSRect?, coordinator: CaptureCoordinator) {
        self.coordinator = coordinator

        let size: NSSize
        let origin: NSPoint

        if let initialFrame {
            size = initialFrame.size
            origin = initialFrame.origin
        } else {
            let screen = NSScreen.main
            let backingScale = screen?.backingScaleFactor ?? 2.0
            var w = CGFloat(image.width) / backingScale
            var h = CGFloat(image.height) / backingScale

            // 限制在屏幕可视区的 85% 以内，超大截图按比例缩小；中小型截图保持 1:1 原尺寸高清显示
            let maxW = (screen?.visibleFrame.width ?? 1200) * 0.85
            let maxH = (screen?.visibleFrame.height ?? 800) * 0.85
            let fitScale = min(1.0, min(maxW / max(1, w), maxH / max(1, h)))
            w = round(w * fitScale)
            h = round(h * fitScale)
            size = NSSize(width: max(80, w), height: max(60, h))

            if let screen {
                origin = NSPoint(
                    x: screen.visibleFrame.midX - size.width / 2,
                    y: screen.visibleFrame.midY - size.height / 2
                )
            } else {
                origin = .zero
            }
        }

        // 1. 主贴图浮窗
        let pinnedPanel = PinnedPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        pinnedPanel.level = .floating
        pinnedPanel.isOpaque = false
        pinnedPanel.backgroundColor = .clear
        pinnedPanel.hasShadow = true
        pinnedPanel.isMovableByWindowBackground = false
        pinnedPanel.hidesOnDeactivate = false
        panel = pinnedPanel

        // 2. 底部工具栏卫星浮窗
        toolbarPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 510, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toolbarPanel.level = .floating
        toolbarPanel.isOpaque = false
        toolbarPanel.backgroundColor = .clear
        toolbarPanel.hasShadow = false
        toolbarPanel.hidesOnDeactivate = false

        // 3. 右侧属性/OCR/翻译卡片卫星浮窗
        sidePanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        sidePanel.level = .floating
        sidePanel.isOpaque = false
        sidePanel.backgroundColor = .clear
        sidePanel.hasShadow = false
        sidePanel.hidesOnDeactivate = false

        imageView = PinnedImageView(frame: NSRect(origin: .zero, size: size), image: image, state: state)
        super.init()

        imageView.onClose = { [weak self] in
            self?.close()
        }
        imageView.onToggleEditing = { [weak self] in
            self?.toggleToolbar()
        }
        imageView.onWindowMovedOrResized = { [weak self] in
            self?.updatePositions()
        }

        (panel as? PinnedPanel)?.onCancel = { [weak self] in
            self?.close()
        }
        (panel as? PinnedPanel)?.onSpace = { [weak self] in
            self?.toggleToolbar()
        }

        panel.contentView = imageView
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.makeKey()

        // 配置工具栏视图
        let toolbarView = PinnedToolbarView(
            state: state,
            pinnedState: pinnedState,
            onUndo: { [weak self] in
                self?.state.undo()
                self?.imageView.needsDisplay = true
            },
            onRedo: { [weak self] in
                self?.state.redo()
                self?.imageView.needsDisplay = true
            },
            onToggleAnnotation: { [weak self] in
                self?.toggleTab(.annotation)
            },
            onToggleTranslate: { [weak self] in
                self?.toggleTab(.translate)
            },
            onToggleOCR: { [weak self] in
                self?.toggleTab(.ocr)
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
        let toolbarHosting = NSHostingView(rootView: toolbarView)
        toolbarHosting.appearance = NSAppearance(named: .aqua)
        toolbarPanel.contentView = toolbarHosting

        // 配置右侧属性/OCR/翻译面板视图
        let sideView = PinnedSidePanelView(
            state: state,
            pinnedState: pinnedState,
            onRunOCR: { [weak self] in self?.runOCR() },
            onCopyAllOCR: { [weak self] in
                guard let self else { return }
                let text = self.pinnedState.ocrLines.map(\.text).joined(separator: "\n")
                self.copyText(text)
            },
            onSaveOCRToNotes: { [weak self] in self?.saveOCRToNotes() },
            onCopyText: { [weak self] text in self?.copyText(text) },
            onRunTranslation: { [weak self] in self?.runTranslation() },
            onCopyAllTranslations: { [weak self] in
                guard let self else { return }
                let text = self.pinnedState.ocrLines.map { self.pinnedState.translations[$0.id] ?? "" }.joined(separator: "\n")
                self.copyText(text)
            },
            onQuickCopy: { [weak self] in self?.copyImage() },
            onClose: { [weak self] in self?.hideSidePanel() }
        )
        let sideHosting = NSHostingView(rootView: sideView)
        sideHosting.appearance = NSAppearance(named: .aqua)
        sidePanel.contentView = sideHosting

        panel.orderFrontRegardless()
    }

    func toggleToolbar() {
        if isToolbarVisible {
            hideAll()
        } else {
            showAll()
        }
    }

    func showAll() {
        guard !isToolbarVisible else { return }
        isToolbarVisible = true
        pinnedState.isSidePanelVisible = true
        pinnedState.panelTab = .ocr

        updatePositions()

        if toolbarPanel.parent != panel {
            panel.addChildWindow(toolbarPanel, ordered: .above)
        }
        toolbarPanel.orderFront(nil)

        if sidePanel.parent != panel {
            panel.addChildWindow(sidePanel, ordered: .above)
        }
        sidePanel.orderFront(nil)

        // 默认自动运行一次 OCR 识别贴图文字
        if pinnedState.ocrPhase == .idle {
            runOCR()
        }
    }

    func hideAll() {
        guard isToolbarVisible else { return }
        isToolbarVisible = false
        pinnedState.isSidePanelVisible = false
        state.activeKind = nil

        toolbarPanel.orderOut(nil)
        panel.removeChildWindow(toolbarPanel)

        sidePanel.orderOut(nil)
        panel.removeChildWindow(sidePanel)

        panel.invalidateCursorRects(for: imageView)
        imageView.needsDisplay = true
    }

    func toggleTab(_ tab: PanelTab) {
        if pinnedState.isSidePanelVisible && pinnedState.panelTab == tab {
            hideSidePanel()
        } else {
            showSidePanel(tab: tab)
        }
    }

    func showSidePanel(tab: PanelTab) {
        pinnedState.panelTab = tab
        pinnedState.isSidePanelVisible = true
        updateSidePanelPosition()
        if sidePanel.parent != panel {
            panel.addChildWindow(sidePanel, ordered: .above)
        }
        sidePanel.orderFront(nil)

        if tab == .ocr && pinnedState.ocrPhase == .idle {
            runOCR()
        } else if tab == .translate {
            runTranslation()
        }
    }

    func hideSidePanel() {
        pinnedState.isSidePanelVisible = false
        sidePanel.orderOut(nil)
        panel.removeChildWindow(sidePanel)
    }

    func updatePositions() {
        updateToolbarPosition()
        updateSidePanelPosition()
    }

    func updateToolbarPosition() {
        guard isToolbarVisible else { return }
        let pFrame = panel.frame
        let barWidth: CGFloat = 510
        let barHeight: CGFloat = 46
        let spacing: CGFloat = 8

        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 2560, height: 1440)

        var x = pFrame.midX - barWidth / 2
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - barWidth - 8))

        var y = pFrame.minY - barHeight - spacing
        if y < visibleFrame.minY + 8 {
            y = pFrame.maxY + spacing
        }

        toolbarPanel.setFrame(NSRect(x: x, y: y, width: barWidth, height: barHeight), display: true)
    }

    func updateSidePanelPosition() {
        guard pinnedState.isSidePanelVisible else { return }
        let pFrame = panel.frame
        let sideWidth: CGFloat = 340
        let sideHeight: CGFloat = 420
        let spacing: CGFloat = 12

        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 2560, height: 1440)

        // 优先放在贴图右侧；若右侧超屏则放左侧
        var x = pFrame.maxX + spacing
        if x + sideWidth > visibleFrame.maxX - 8 {
            x = pFrame.minX - sideWidth - spacing
        }
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - sideWidth - 8))

        var y = pFrame.maxY - sideHeight
        y = max(visibleFrame.minY + 8, min(y, visibleFrame.maxY - sideHeight - 8))

        sidePanel.setFrame(NSRect(x: x, y: y, width: sideWidth, height: sideHeight), display: true)
    }

    func close() {
        pinnedState.ocrTask?.cancel()
        pinnedState.translationTask?.cancel()
        hideAll()
        toolbarPanel.close()
        sidePanel.close()
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

    func runOCR(thenTranslate: Bool = false) {
        pinnedState.ocrTask?.cancel()
        pinnedState.ocrPhase = .running
        pinnedState.ocrErrorMessage = nil
        pinnedState.ocrLines = []
        pinnedState.translations = [:]
        pinnedState.translationPhase = .idle
        pinnedState.justSavedNote = false

        let composited = imageView.renderCompositedImage()
        pinnedState.ocrTask = Task {
            do {
                let lines = try await ProviderRegistry.ocr.recognizeText(in: composited, languages: ["zh-Hans", "en-US"])
                guard !Task.isCancelled else { return }
                pinnedState.ocrLines = lines
                pinnedState.ocrPhase = lines.isEmpty ? .empty : .done
                if thenTranslate, !lines.isEmpty {
                    pinnedState.panelTab = .translate
                    runTranslation()
                }
            } catch {
                guard !Task.isCancelled else { return }
                pinnedState.ocrPhase = .failed
                pinnedState.ocrErrorMessage = error.localizedDescription
            }
        }
    }

    func runTranslation() {
        pinnedState.panelTab = .translate
        if pinnedState.ocrLines.isEmpty {
            runOCR(thenTranslate: true)
            return
        }
        translateLines()
    }

    private func translateLines() {
        pinnedState.translationTask?.cancel()
        pinnedState.translationPhase = .running
        pinnedState.translationErrorMessage = nil
        let lines = pinnedState.ocrLines
        pinnedState.translationTask = Task {
            var results: [UUID: String] = [:]
            var firstError: String?
            for line in lines {
                guard !Task.isCancelled else { return }
                do {
                    let target = ProviderRegistry.translation.defaultTargetLanguage(for: line.text)
                    let translated = try await ProviderRegistry.translation.translate(line.text, from: nil, to: target)
                    results[line.id] = translated
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                    results[line.id] = ""
                }
            }
            guard !Task.isCancelled else { return }
            pinnedState.translations = results
            if let firstError, results.values.allSatisfy({ $0.isEmpty }) {
                pinnedState.translationPhase = .failed
                pinnedState.translationErrorMessage = firstError
            } else {
                pinnedState.translationPhase = .done
                pinnedState.translationErrorMessage = nil
            }
        }
    }

    func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ClipboardMonitor.shared.markSelfWrite()
        SaveToastController.shared.show(
            title: "已复制文本",
            subtitle: String(text.prefix(35)) + (text.count > 35 ? "..." : ""),
            thumbnail: nil
        )
    }

    func saveOCRToNotes() {
        let content = pinnedState.ocrLines.map(\.text).joined(separator: "\n")
        guard !content.isEmpty else { return }
        do {
            _ = try ScreenshotStore.shared.createTextNote(content: content, sourceApp: "lenso 贴图识别")
            pinnedState.justSavedNote = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                pinnedState.justSavedNote = false
            }
        } catch {
            pinnedState.ocrErrorMessage = "存入失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 贴图右侧属性/OCR/翻译面板视图

private struct PinnedSidePanelView: View {
    @Bindable var state: AnnotationState
    @Bindable var pinnedState: PinnedEditorState
    let onRunOCR: () -> Void
    let onCopyAllOCR: () -> Void
    let onSaveOCRToNotes: () -> Void
    let onCopyText: (String) -> Void
    let onRunTranslation: () -> Void
    let onCopyAllTranslations: () -> Void
    let onQuickCopy: () -> Void
    let onClose: () -> Void

    @State private var ocrDisplayMode = 0
    @State private var translationDisplayMode = 0

    var body: some View {
        VStack(spacing: 14) {
            // 顶部工具行：标注 / 翻译 / OCR / 关闭
            HStack(spacing: 16) {
                SideTool(icon: "highlighter", label: "标注", active: pinnedState.panelTab == .annotation) {
                    pinnedState.panelTab = .annotation
                    state.activeKind = .brush
                }
                SideTool(icon: "character.bubble", label: "翻译", active: pinnedState.panelTab == .translate) {
                    pinnedState.panelTab = .translate
                    onRunTranslation()
                }
                SideTool(icon: "doc.text.viewfinder", label: "OCR", active: pinnedState.panelTab == .ocr) {
                    pinnedState.panelTab = .ocr
                    if pinnedState.ocrPhase == .idle { onRunOCR() }
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("关闭面板")
            }

            switch pinnedState.panelTab {
            case .annotation:
                annotationControls
            case .ocr:
                ocrResultsView
            case .translate:
                translationResultsView
            }
        }
        .padding(16)
        .frame(width: 340)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.985, green: 0.988, blue: 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 20, y: 6)
    }

    private var annotationControls: some View {
        Group {
            // 颜色盘（7 色）
            HStack(spacing: 12) {
                ForEach(0..<AnnotationPalette.count, id: \.self) { i in
                    Circle()
                        .fill(AnnotationPalette[i])
                        .frame(width: 22, height: 22)
                        .overlay {
                            if state.colorIndex == i {
                                Circle().strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2.5)
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .onTapGesture { state.colorIndex = i }
                }
            }

            // 粗细滑杆 + Npx
            HStack(spacing: 10) {
                Slider(value: $state.strokeWidth, in: 1...10, step: 1)
                    .tint(Color(nsColor: .controlAccentColor))
                Text("\(Int(state.strokeWidth))px")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
            }

            // 形状快捷行
            HStack(spacing: 22) {
                ShapeQuick(icon: "line.diagonal", kind: .brush, state: state) { state.activeKind = .brush }
                ShapeQuick(icon: "arrow.right", kind: .arrow, state: state) { state.activeKind = .arrow }
                ShapeQuick(icon: "rectangle", kind: .rect, state: state) { state.activeKind = .rect }
                ShapeQuick(icon: "circle", kind: .ellipse, state: state) { state.activeKind = .ellipse }
                ShapeQuick(icon: "arrow.up.right", kind: .arrow, state: state) { state.activeKind = .arrow }
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.04)))

            // 马赛克 / 高亮 开关行
            ToggleRow(icon: "square.grid.3x3.square", label: "马赛克", isOn: $state.mosaicEnabled) {
                if state.mosaicEnabled { state.activeKind = .mosaic }
            }
            ToggleRow(icon: "drop", label: "高亮", isOn: $state.highlightEnabled) {
                if state.highlightEnabled { state.activeKind = .highlight }
            }

            // 复制到剪贴板
            Button {
                onQuickCopy()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("复制到剪贴板").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("⌘C").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.05)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var ocrResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("识别结果").font(.system(size: 13, weight: .semibold))
                if !pinnedState.ocrLines.isEmpty {
                    Picker("", selection: $ocrDisplayMode) {
                        Text("全文展开").tag(0)
                        Text("逐行对照").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .controlSize(.mini)
                }
                Spacer()
                if pinnedState.ocrPhase == .running { ProgressView().controlSize(.small) }
            }
            switch pinnedState.ocrPhase {
            case .idle:
                Text("对当前贴图做文字识别（本地 Vision，不联网）。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在识别中…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            case .empty:
                Text("当前贴图中没识别到文字。").font(.system(size: 12)).foregroundStyle(.secondary)
            case .failed:
                Text(pinnedState.ocrErrorMessage ?? "识别失败").font(.system(size: 12)).foregroundStyle(.red)
            case .done:
                if ocrDisplayMode == 0 {
                    ScrollView {
                        Text(pinnedState.ocrLines.map(\.text).joined(separator: "\n"))
                            .font(.system(size: 13, weight: .regular))
                            .lineSpacing(4)
                            .lineLimit(nil)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.03)))
                    .frame(maxHeight: 280)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(pinnedState.ocrLines) { line in
                                OCRLineRow(line: line) { onCopyText(line.text) }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            HStack(spacing: 8) {
                MiniButton(label: "重新识别") { onRunOCR() }
                MiniButton(label: "全部复制", disabled: pinnedState.ocrLines.isEmpty) { onCopyAllOCR() }
                MiniButton(label: pinnedState.justSavedNote ? "已存入" : "存入收纳", disabled: pinnedState.ocrLines.isEmpty) { onSaveOCRToNotes() }
            }
        }
    }

    private var translationResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("翻译结果").font(.system(size: 13, weight: .semibold))
                if !pinnedState.translations.isEmpty {
                    Picker("", selection: $translationDisplayMode) {
                        Text("译文全文").tag(0)
                        Text("逐行对照").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .controlSize(.mini)
                }
                Spacer()
                if pinnedState.translationPhase == .running { ProgressView().controlSize(.small) }
            }
            switch pinnedState.translationPhase {
            case .idle:
                Text("把识别到的文字翻成目标语言（本地模型，不联网）。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在翻译中…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            case .failed:
                Text(pinnedState.translationErrorMessage ?? "翻译失败").font(.system(size: 12)).foregroundStyle(.red)
            case .done:
                if translationDisplayMode == 0 {
                    ScrollView {
                        let text = pinnedState.ocrLines.map { pinnedState.translations[$0.id] ?? "" }.filter { !$0.isEmpty }.joined(separator: "\n")
                        Text(text)
                            .font(.system(size: 13, weight: .regular))
                            .lineSpacing(4)
                            .lineLimit(nil)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.03)))
                    .frame(maxHeight: 280)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(pinnedState.ocrLines) { line in
                                TranslationLineRow(
                                    original: line.text,
                                    translated: pinnedState.translations[line.id] ?? ""
                                ) {
                                    let translated = pinnedState.translations[line.id] ?? ""
                                    onCopyText(translated.isEmpty ? line.text : translated)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            HStack(spacing: 8) {
                MiniButton(label: "重新翻译") { onRunTranslation() }
                MiniButton(label: "全部复制译文", disabled: pinnedState.translations.isEmpty) { onCopyAllTranslations() }
            }
        }
    }
}

// MARK: - 贴图工具栏视图（SwiftUI 高对比胶囊浮条）

private struct PinnedToolbarView: View {
    @Bindable var state: AnnotationState
    @Bindable var pinnedState: PinnedEditorState
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleAnnotation: () -> Void
    let onToggleTranslate: () -> Void
    let onToggleOCR: () -> Void
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
                    .foregroundStyle(state.activeKind == nil ? .white : Color(red: 0.18, green: 0.18, blue: 0.22))
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
                        .foregroundStyle(state.activeKind == kind ? Color(nsColor: .controlAccentColor) : Color(red: 0.18, green: 0.18, blue: 0.22))
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

            // 标注属性面板快捷入口（点击打开标注设置卡片）
            Button(action: onToggleAnnotation) {
                Circle()
                    .fill(AnnotationPalette[state.colorIndex])
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 1))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(pinnedState.isSidePanelVisible && pinnedState.panelTab == .annotation ? Color(nsColor: .controlAccentColor).opacity(0.15) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .help("标注调色盘与粗细设置")

            Divider().frame(height: 18)

            // 撤销 / 重做
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22).opacity(state.canUndo ? 1.0 : 0.35))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!state.canUndo)
            .help("撤销 (⌘Z)")

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22).opacity(state.canRedo ? 1.0 : 0.35))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!state.canRedo)
            .help("重做 (⇧⌘Z)")

            Divider().frame(height: 18)

            // 翻译
            Button(action: onToggleTranslate) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pinnedState.isSidePanelVisible && pinnedState.panelTab == .translate ? Color(nsColor: .controlAccentColor) : Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(pinnedState.isSidePanelVisible && pinnedState.panelTab == .translate ? Color(nsColor: .controlAccentColor).opacity(0.15) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .help("智能翻译卡片")

            // OCR
            Button(action: onToggleOCR) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pinnedState.isSidePanelVisible && pinnedState.panelTab == .ocr ? Color(nsColor: .controlAccentColor) : Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(pinnedState.isSidePanelVisible && pinnedState.panelTab == .ocr ? Color(nsColor: .controlAccentColor).opacity(0.15) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .help("文字识别 (OCR) 卡片")

            // 复制
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("复制到剪贴板 (⌘C)")

            // 保存
            Button(action: onSave) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("保存到历史记录 (⌘S)")

            // 关闭
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("关闭贴图")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color(red: 0.985, green: 0.988, blue: 1.0))
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
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

    // 窗口平滑拖拽与双击判定（不使用阻塞的 performDrag，避免吞掉第二次点击）
    private var initialMouseScreenLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private var isDraggingWindow = false

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

        // 选择 / 移动模式：双击或多次快速点击立即 100% 灵敏关闭
        if state.activeKind == nil {
            if event.clickCount >= 2 {
                onClose?()
                return
            }
            initialMouseScreenLocation = NSEvent.mouseLocation
            initialWindowOrigin = window?.frame.origin ?? .zero
            isDraggingWindow = true
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
        if state.activeKind == nil && isDraggingWindow {
            guard let window else { return }
            let currentMouse = NSEvent.mouseLocation
            let dx = currentMouse.x - initialMouseScreenLocation.x
            let dy = currentMouse.y - initialMouseScreenLocation.y
            window.setFrameOrigin(NSPoint(x: initialWindowOrigin.x + dx, y: initialWindowOrigin.y + dy))
            onWindowMovedOrResized?()
            return
        }

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
        if state.activeKind == nil {
            isDraggingWindow = false
            onWindowMovedOrResized?()
            return
        }

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
