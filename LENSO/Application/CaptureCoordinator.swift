import AppKit
import CoreGraphics
import OSLog

extension Notification.Name {
    static let screenshotSaved = Notification.Name("com.lenso.screenshotSaved")
}

private let log = Logger(subsystem: "com.lenso.app", category: "capture")

/// 截图流程编排（规范 6.1）：权限 → 选区 → 截图 → 保存 → 剪贴板 → 通知
@MainActor
final class CaptureCoordinator: NSObject {
    static let shared = CaptureCoordinator()

    private let capture = ScreenCaptureService()
    private var selector: RegionSelectorController?

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
                await self?.captureAndSave(rect: rect, displayID: displayID, service: captureService)
            }
        }
    }

    private func captureAndSave(rect: CGRect, displayID: CGDirectDisplayID, service: ScreenCaptureService) async {
        do {
            log.info("capturing region \(NSStringFromRect(rect), privacy: .public) on display \(displayID)")
            let result = try await service.captureRegion(rect, displayID: displayID)
            let record = try ScreenshotStore.shared.save(image: result.image, capturedAt: Date())
            copyToClipboard(image: result.image)
            NotificationCenter.default.post(name: .screenshotSaved, object: record)
            NSSound.beep() // 轻反馈；正式版换成可配置提示音
            log.info("saved \(record.filename, privacy: .public)")
        } catch {
            NSSound.beep()
            // MVP：失败仅日志，不打断用户（规范 17 章后续完善错误提示）
            log.error("capture failed: \(error.localizedDescription, privacy: .public)")
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
