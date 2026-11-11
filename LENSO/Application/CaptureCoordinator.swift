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
    /// 钉图窗口集合（持有引用防止释放）
    private var pinnedPanels: [NSPanel] = []

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
        initialSelection: CGRect,
        originPinnedPanel: NSPanel? = nil
    ) {
        let coordinator = self
        let editorView = CaptureEditorView(
            frozenImage: frozen,
            screenFrame: screenFrame,
            initialSelection: initialSelection,
            onComplete: { [weak coordinator] finalImage in
                coordinator?.closeEditor()
                if let finalImage {
                    if let origin = originPinnedPanel {
                        origin.orderOut(nil)
                        origin.close()
                        coordinator?.pinnedPanels.removeAll { $0 === origin }
                    }
                    coordinator?.handleFinish(finalImage: finalImage)
                } else {
                    // 取消/丢弃：如果来自贴图，重新显示贴图
                    originPinnedPanel?.orderFrontRegardless()
                }
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
                if let origin = originPinnedPanel {
                    origin.orderOut(nil)
                    origin.close()
                    coordinator?.pinnedPanels.removeAll { $0 === origin }
                }
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
            originPinnedPanel?.orderFrontRegardless()
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

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        let view = PinnedImageView(frame: NSRect(origin: .zero, size: size), image: image)
        view.onClose = { [weak panel, weak self] in
            guard let panel else { return }
            panel.orderOut(nil)
            panel.close()
            self?.pinnedPanels.removeAll { $0 === panel }
        }
        view.onEdit = { [weak panel, weak self] in
            guard let panel, let self else { return }
            self.editPinnedScreenshot(panel: panel, image: image)
        }
        panel.contentView = view
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        pinnedPanels.append(panel)
        log.info("pinned image \(size.width)x\(size.height) at \(NSStringFromPoint(origin))")
    }

    /// 右键钉图唤出全功能编辑器（Snipaste 核心交互）
    private func editPinnedScreenshot(panel: NSPanel, image: CGImage) {
        guard editorPanel == nil else { return }
        log.info("editPinnedScreenshot triggered for panel frame: \(NSStringFromRect(panel.frame))")

        let screen = panel.screen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let screenFrame = screen.frame
        let panelFrame = panel.frame
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
            ?? CGMainDisplayID()

        let captureService = capture
        Task { @MainActor in
            do {
                // 抓取当前屏幕画面（排除当前贴图面板）
                let windowID = CGWindowID(panel.windowNumber)
                let screenFrozen = try await captureService.captureDisplayExcluding(
                    displayID: displayID,
                    excludedWindowIDs: [windowID]
                )
                // 将高清贴图精确合成回屏幕冻结帧对应位置
                let compositeFrozen = self.composite(
                    image: image,
                    onto: screenFrozen,
                    at: panelFrame,
                    screenFrame: screenFrame
                )
                panel.orderOut(nil)
                self.showFullEditor(
                    frozen: compositeFrozen,
                    screenFrame: screenFrame,
                    initialSelection: panelFrame,
                    originPinnedPanel: panel
                )
            } catch {
                log.error("capture failed for pinned edit: \(error.localizedDescription)")
                panel.orderFrontRegardless()
            }
        }
    }

    /// 将贴图图像精准复合到全屏截图中对应选区位置
    private func composite(
        image: CGImage,
        onto screenImage: CGImage,
        at rect: CGRect,
        screenFrame: CGRect
    ) -> CGImage {
        let scale = CGFloat(screenImage.width) / max(1, screenFrame.width)
        let w = screenImage.width
        let h = screenImage.height

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return screenImage
        }

        ctx.draw(screenImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let destX = (rect.minX - screenFrame.minX) * scale
        let destY = (rect.minY - screenFrame.minY) * scale
        let destW = rect.width * scale
        let destH = rect.height * scale
        let destRect = CGRect(x: destX, y: destY, width: destW, height: destH)

        ctx.draw(image, in: destRect)
        return ctx.makeImage() ?? screenImage
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

    private func copyToClipboard(image: CGImage) {
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

/// 钉图视图：可拖动；滚轮缩放；悬停右上角出现关闭按钮；双击关闭；右键唤出全功能编辑栏
final class PinnedImageView: NSView {
    var onClose: (() -> Void)?
    var onEdit: (() -> Void)?
    let image: CGImage
    private let imageView: NSImageView
    private let closeButton = NSButton()
    private var tracking: NSTrackingArea?
    private let baseSize: NSSize
    private var currentScale: CGFloat = 1.0

    init(frame: NSRect, image: CGImage) {
        self.image = image
        self.baseSize = frame.size
        imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(frame: frame)
        toolTip = "双击关闭 · 滚轮缩放 · 鼠标右键重新编辑"
        imageView.image = NSImage(cgImage: image, size: frame.size)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        addSubview(imageView)

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view == closeButton { return closeButton }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onClose?()
            return
        }
        super.mouseDown(with: event)
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onEdit?()
    }

    override func keyDown(with event: NSEvent) {
        // 空格键快捷唤出编辑栏
        if event.keyCode == 49 {
            onEdit?()
            return
        }
        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    /// 鼠标滚轮放大缩小贴图（Snipaste 核心交互）
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.05 else { return }

        // 向上滚放大，向下滚缩小（缩放区间 15% ~ 500%）
        let zoomFactor: CGFloat = delta > 0 ? 1.08 : 0.92
        let newScale = min(max(currentScale * zoomFactor, 0.15), 5.0)
        guard newScale != currentScale else { return }

        currentScale = newScale
        guard let window else { return }

        let mouseScreen = NSEvent.mouseLocation
        let oldFrame = window.frame
        let newWidth = max(40, round(baseSize.width * newScale))
        let newHeight = max(40, round(baseSize.height * newScale))

        // 以鼠标指针在当前窗口内的相对位置为锚点缩放
        let relX = (mouseScreen.x - oldFrame.minX) / max(1, oldFrame.width)
        let relY = (mouseScreen.y - oldFrame.minY) / max(1, oldFrame.height)

        let newX = mouseScreen.x - newWidth * relX
        let newY = mouseScreen.y - newHeight * relY
        let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)

        window.setFrame(newFrame, display: true)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }
}
