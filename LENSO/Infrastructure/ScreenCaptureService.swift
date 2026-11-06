import ScreenCaptureKit
import CoreGraphics
import AppKit

struct RegionCaptureResult {
    let image: CGImage
    /// 逻辑坐标（全局屏幕坐标系，原点左上）
    let rect: CGRect
    let displayID: CGDirectDisplayID
}

enum CaptureError: LocalizedError {
    case displayNotFound(CGDirectDisplayID)
    case cropFailed
    case emptyRegion

    var errorDescription: String? {
        switch self {
        case .displayNotFound(let id): "找不到显示器 \(id)"
        case .cropFailed: "截图裁剪失败"
        case .emptyRegion: "选区为空"
        }
    }
}

/// 区域截图引擎（对应规范 POC-01/02：SCScreenshotManager 全屏抓取 + 按选区裁剪）
final class ScreenCaptureService: Sendable {
    func captureRegion(_ rect: CGRect, displayID: CGDirectDisplayID) async throws -> RegionCaptureResult {
        guard rect.width >= 1, rect.height >= 1 else { throw CaptureError.emptyRegion }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound(displayID)
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        config.captureResolution = .best

        let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        // 像素坐标 = (逻辑坐标 - 显示器原点) × 像素密度
        // 截图实际尺寸 vs 显示器点尺寸 推断 scale（SCDisplay 无 scale 属性）
        let scaleX = CGFloat(fullImage.width) / CGFloat(display.width)
        let scaleY = CGFloat(fullImage.height) / CGFloat(display.height)
        let pxRect = CGRect(
            x: (rect.origin.x - display.frame.origin.x) * scaleX,
            y: (rect.origin.y - display.frame.origin.y) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral

        guard let cropped = fullImage.cropping(to: pxRect), cropped.width > 0, cropped.height > 0 else {
            throw CaptureError.cropFailed
        }
        return RegionCaptureResult(image: cropped, rect: rect, displayID: displayID)
    }
}
