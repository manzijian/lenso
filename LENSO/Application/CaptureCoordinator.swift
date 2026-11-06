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
    /// 置顶窗口由 WindowKit 后续管理；MVP 用独立轻量窗口
    private var pinnedPanel: NSPanel?

    func startRegionCapture() {
        log.info("startRegionCapture triggered")
        Task { await startRegionCaptureAsync() }
    }

    private func startRegionCaptureAsync() async {
        // 渐进式权限：首次截图时申请
        if CapturePermissionService.currentStatus() != .authorized {
            log.info("permission not authorized, requesting")
            let status = await CapturePermissionService.requestAccess()
            guard status == .authorized else {
                log.error("permission still denied after request")
                return
            }
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

    /// 置顶：无标题透明悬浮窗口，右键或点击关闭按钮关闭
    private func pin(image: CGImage) {
        let size = NSSize(width: min(CGFloat(image.width), 480), height: CGFloat(image.height) * min(1, 480 / CGFloat(image.width)))
        let panel = NSPanel(
            contentRect: NSRect(origin: NSEvent.mouseLocation, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = NSImage(cgImage: image, size: size)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let container = PinnedImageView(imageView: imageView, onClose: { [weak panel] in panel?.close() })
        panel.contentView = container
        panel.orderFrontRegardless()
        self.pinnedPanel = panel
    }

    private func copyToClipboard(image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}

/// 置顶图视图：悬停显示关闭按钮
private final class PinnedImageView: NSView {
    private let closeButton: NSButton
    private var hoverTracking: NSTrackingArea?

    init(imageView: NSImageView, onClose: @escaping () -> Void) {
        closeButton = NSButton(title: "✕", target: nil, action: nil)
        super.init(frame: imageView.frame)
        addSubview(imageView)
        closeButton.bezelStyle = .circular
        closeButton.controlSize = .small
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = nil
        closeButton.action = #selector(closeClicked)
        addSubview(closeButton)
        closeButton.isHidden = true
        self.onClose = onClose
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }

    private var onClose: (() -> Void)?

    @objc private func closeClicked() { onClose?() }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }
}
