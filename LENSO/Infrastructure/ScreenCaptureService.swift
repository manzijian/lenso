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
