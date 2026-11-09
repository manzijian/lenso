import ScreenCaptureKit
import CoreGraphics
import AppKit

enum CaptureError: LocalizedError {
    case displayNotFound(CGDirectDisplayID)

    var errorDescription: String? {
        switch self {
        case .displayNotFound(let id): "找不到显示器 \(id)"
        }
    }
}

/// 区域截图引擎（丝滑 v2：确认后抓图）。
///
/// 选区阶段不再预抓冻结图（那是 v1 卡顿的主因：快捷键按下后要等每显示器
/// 一张全屏 captureImage 抓完，面板才出现）。
/// 确认那一刻，选区面板还在台上时抓一张全屏图，把选区面板按窗口 ID
/// 排除在外，当编辑器背景；抓完开编辑器、再关选区，中间不露桌面。
/// 主窗口不排除——它是可以被截的（Ta 的原则：自己的窗口保持可见时能被截图）。
final class ScreenCaptureService: Sendable {
    /// 放大镜取样：抓光标周围 12×8 个设备像素，返回图像与取样矩形。
    ///
    /// CGWindowListCreateImage 在 macOS 15 起被标记为 obsoleted（编译期直接
    /// 报错："Please use ScreenCaptureKit instead."），所以这里改走 ScreenCaptureKit：
    /// display filter 排除选区面板窗口（否则取到的是被压暗的像素），
    /// sourceRect 只取光标周围那一小块，输出固定 12×8 像素。
    ///
    /// 坐标系：返回的 rect 是显示器内坐标、原点在显示器左上（与 ScreenCaptureKit
    /// 一致）；调用方要换算成 AppKit 全局坐标自己再翻一次。
    func captureMagnifierSample(
        displayID: CGDirectDisplayID,
        displayFrame: CGRect,
        around globalPoint: CGPoint,
        excludedWindowIDs: [CGWindowID]
    ) async throws -> MagnifierSample {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound(displayID)
        }
        let excluded = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        // 12×8 个设备像素 = 12/scale × 8/scale 个点（Retina 上 scale=2）
        let scale = CGFloat(CGDisplayPixelsWide(displayID)) / max(1, displayFrame.width)
        let w = 12 / scale
        let h = 8 / scale
        // 显示器内坐标，原点左上：x 从左边算，y 从上边算
        let dx = globalPoint.x - displayFrame.origin.x
        let dyTop = displayFrame.height - (globalPoint.y - displayFrame.origin.y)
        let rect = CGRect(x: dx - w / 2, y: dyTop - h / 2, width: w, height: h)
            .intersection(CGRect(origin: .zero, size: displayFrame.size))
        config.sourceRect = rect
        config.width = 12
        config.height = 8
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return MagnifierSample(image: image, rect: rect)
    }
    /// 抓指定显示器的全屏图（物理像素），排除给定的窗口（选区面板）。
    func captureDisplayExcluding(displayID: CGDirectDisplayID, excludedWindowIDs: [CGWindowID]) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound(displayID)
        }
        let excluded = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        // Retina：用物理像素，否则输出 1x 图像显示时拉伸模糊
        config.width = Int(CGDisplayPixelsWide(displayID))
        config.height = Int(CGDisplayPixelsHigh(displayID))
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

/// 放大镜的一次取样结果：图像 + 取样矩形（显示器内坐标，原点左上）。
struct MagnifierSample: Sendable {
    let image: CGImage
    let rect: CGRect
}
