import AppKit
import CoreGraphics
import OSLog
import SwiftUI

extension Notification.Name {
    static let screenshotSaved = Notification.Name("com.lenso.screenshotSaved")
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
    /// 屏幕录制权限已验证通过（TCC 状态会话内几乎不变，通过一次后不再重复探测）
    private var permissionKnownGood = false

    func startRegionCapture() {
        log.info("startRegionCapture triggered")
        Task { await startRegionCaptureAsync() }
    }

    private func startRegionCaptureAsync() async {
        // 以真实能力为准（preflight 对 ad-hoc 调试构建不可靠）
        // 权限通过后会话内缓存，不再每次截图都枚举 SCShareableContent
        var allowed = permissionKnownGood ? true : await CapturePermissionService.probeAccess()
        if allowed {
            permissionKnownGood = true
        } else {
            log.info("probe failed, requesting permission")
            let status = await CapturePermissionService.requestAccess()
            allowed = status == .authorized
            if allowed { permissionKnownGood = true }
        }
        guard allowed else {
            log.error("screen capture not permitted")
            NSSound.beep()
            return
        }

        // 丝滑 v2：面板立刻上屏（不预抓图），选区里透出实时桌面。
        // 确认后才抓一张全屏当编辑器背景，抓时把选区面板排除在外。
        let selector = RegionSelectorController()
        self.selector = selector
        let captureService = capture
        selector.begin { [weak self, weak selector] rect, displayID, panelWindowNumber in
            Task { @MainActor in
                guard let self, let selector, !selector.isDismissed else { return }
                do {
                    // 选区还在台上时先抓图（面板已排除），再开编辑器，最后关选区
                    let frozen = try await captureService.captureDisplayExcluding(
                        displayID: displayID, excludedWindowIDs: [panelWindowNumber]
                    )
                    let screenFrame = NSScreen.screens
                        .first(where: {
                            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID == displayID
                        })?
                        .frame ?? rect
                    self.showFullEditor(frozen: frozen, screenFrame: screenFrame, initialSelection: rect)
                    selector.dismiss()
                    self.selector = nil
                } catch {
                    NSSound.beep()
                    log.error("capture failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func showFullEditor(frozen: CGImage, screenFrame: CGRect, initialSelection: CGRect) {
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
                SaveToastController.shared.show(thumbnail: image)
            },
            onPin: { [weak coordinator] image in
                coordinator?.closeEditor()
                coordinator?.pin(image: image)
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
        log.info("full editor shown")
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
            copyToClipboard(image: image)
            NotificationCenter.default.post(name: .screenshotSaved, object: record)
            SaveToastController.shared.show(thumbnail: try? ScreenshotStore.shared.loadThumbnail(record))
            NSSound.beep()
            log.info("saved \(record.filename, privacy: .public)")
        } catch {
            NSSound.beep()
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 钉图：浮在所有窗口之上的可拖动图片窗
    private func pin(image: CGImage) {
        let maxWidth: CGFloat = 520
        let scale = min(1, maxWidth / CGFloat(image.width))
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        view.onClose = { [weak panel] in
            panel?.orderOut(nil)
            panel?.close()
        }
        panel.contentView = view
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2
            ))
        }
        panel.orderFrontRegardless()
        pinnedPanels.append(panel)
        log.info("pinned image \(size.width)x\(size.height)")
    }

    private func copyToClipboard(image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}

/// 编辑器覆盖面板：Esc 取消
final class EditorPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// 钉图视图：可拖动；悬停右上角出现关闭按钮；双击关闭
final class PinnedImageView: NSView {
    var onClose: (() -> Void)?
    private let imageView: NSImageView
    private let closeButton = NSButton()
    private var tracking: NSTrackingArea?

    init(frame: NSRect, image: CGImage) {
        imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(frame: frame)
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

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onClose?()
            return
        }
        super.mouseDown(with: event)
        window?.performDrag(with: event)
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
