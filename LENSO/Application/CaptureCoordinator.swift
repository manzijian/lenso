import AppKit
import CoreGraphics
import OSLog
import ScreenCaptureKit
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

    func startRegionCapture() {
        log.info("startRegionCapture triggered")
        Task { await startRegionCaptureAsync() }
    }

    private func startRegionCaptureAsync() async {
        // 以真实能力为准（preflight 对 ad-hoc 调试构建不可靠）
        var allowed = await CapturePermissionService.probeAccess()
        if !allowed {
            log.info("probe failed, requesting permission")
            let status = await CapturePermissionService.requestAccess()
            allowed = status == .authorized
        }
        guard allowed else {
            log.error("screen capture not permitted")
            NSSound.beep()
            return
        }
        log.info("permission ok, showing selector")

        let selector = RegionSelectorController()
        self.selector = selector
        let captureService = capture
        selector.begin { [weak self] rect, displayID in
            self?.selector = nil
            Task { @MainActor in
                await self?.beginEdit(rect: rect, displayID: displayID, service: captureService)
            }
        }
    }

    /// 选区完成 → 抓帧 → 显示完整编辑器（冻结全屏 + 标注工具）
    private func beginEdit(rect: CGRect, displayID: CGDirectDisplayID, service: ScreenCaptureService) async {
        do {
            log.info("capturing region \(NSStringFromRect(rect), privacy: .public) on display \(displayID)")
            let result = try await service.captureRegion(rect, displayID: displayID)

            // 冻结整屏（选区外也要展示，供用户调整选区）
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
            let ownApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter: SCContentFilter
            if let ownApp {
                filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
            let config = SCStreamConfiguration()
            // Retina：用物理像素，否则输出 1x 图像显示时拉伸模糊
            let displayID = display.displayID
            let pixelWidth = CGDisplayPixelsWide(displayID)
            let pixelHeight = CGDisplayPixelsHigh(displayID)
            config.width = pixelWidth
            config.height = pixelHeight
            config.showsCursor = true
            config.captureResolution = .best
            let frozen = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            let screenFrame = NSScreen.screens
                .first(where: {
                    $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID == displayID
                })?
                .frame ?? rect

            showFullEditor(frozen: frozen, screenFrame: screenFrame, initialSelection: rect)
        } catch {
            NSSound.beep()
            log.error("capture failed: \(error.localizedDescription, privacy: .public)")
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

        let panel = NSPanel(
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
