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

        // 丝滑关键：先抓图、后上屏。冻结图一次性抓好（每显示器一张），
        // 选区面板出现时图已就位；选区裁剪和编辑器背景全程复用同一张图，
        // 不再每步现抓（旧版一次截图要做 3 次全屏 captureImage）。
        let frozenFrames: [CGDirectDisplayID: CGImage]
        do {
            frozenFrames = try await captureFrozenFrames()
        } catch {
            log.error("freeze failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
            return
        }
        log.info("frozen \(frozenFrames.count) display(s), showing selector")

        let selector = RegionSelectorController()
        self.selector = selector
        let captureService = capture
        selector.begin(frozenFrames: frozenFrames) { [weak self, weak selector] rect, displayID in
            Task { @MainActor in
                guard let self, let selector, !selector.isDismissed else { return }
                // 编辑器先上、选区面板后关，中间不露桌面（零闪烁切换）
                self.beginEdit(
                    rect: rect,
                    displayID: displayID,
                    frozenImage: frozenFrames[displayID],
                    service: captureService
                )
                selector.dismiss()
                self.selector = nil
            }
        }
    }

    /// 一次抓一张全屏冻结图（每显示器，物理像素），供选区、裁剪、编辑器复用。
    /// 只枚举一次内容、只抓一次图；`showsCursor = false`，冻结图里不留假光标。
    private func captureFrozenFrames() async throws -> [CGDirectDisplayID: CGImage] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        // WWDC22 建议：按应用排除自身（本 app 所有窗口），防止 overlay/主窗口入镜
        let ownApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        var frames: [CGDirectDisplayID: CGImage] = [:]
        for display in content.displays {
            let filter: SCContentFilter
            if let ownApp {
                filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
            let config = SCStreamConfiguration()
            // Retina：用物理像素，否则输出 1x 图像显示时拉伸模糊
            config.width = Int(CGDisplayPixelsWide(display.displayID))
            config.height = Int(CGDisplayPixelsHigh(display.displayID))
            config.showsCursor = false
            config.captureResolution = .best
            frames[display.displayID] = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
        }
        return frames
    }

    /// 选区完成 → 从缓存冻结图裁剪 → 显示完整编辑器（同步，无抓图、无闪烁）
    private func beginEdit(
        rect: CGRect,
        displayID: CGDirectDisplayID,
        frozenImage: CGImage?,
        service: ScreenCaptureService
    ) {
        // 极少数情况缓存里没有该显示器的帧（显示器中途插拔）：回退到旧版现抓路径
        guard let frozenImage else {
            Task { await self.beginEditLegacy(rect: rect, displayID: displayID, service: service) }
            return
        }
        let screenFrame = NSScreen.screens
            .first(where: {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID == displayID
            })?
            .frame ?? rect
        do {
            // 只做裁剪校验（矩形越界、显示器变化时快速失败），不抓图
            _ = try service.cropRegion(rect, displayID: displayID, displayFrame: screenFrame, frozenImage: frozenImage)
            showFullEditor(frozen: frozenImage, screenFrame: screenFrame, initialSelection: rect)
        } catch {
            NSSound.beep()
            log.error("capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 回退路径：缓存未命中时按旧版流程现抓一张全屏图当编辑器背景
    private func beginEditLegacy(rect: CGRect, displayID: CGDirectDisplayID, service: ScreenCaptureService) async {
        do {
            log.info("legacy capture for region \(NSStringFromRect(rect), privacy: .public) on display \(displayID)")
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
            config.width = Int(CGDisplayPixelsWide(display.displayID))
            config.height = Int(CGDisplayPixelsHigh(display.displayID))
            config.showsCursor = false
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
