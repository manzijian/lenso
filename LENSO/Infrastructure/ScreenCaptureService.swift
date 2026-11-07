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

/// 区域截图引擎（丝滑修复后：只做纯裁剪，不再抓全屏）。
///
/// 冻结图由 CaptureCoordinator 在选区开始前一次性抓好（每显示器一张，
/// 物理像素），选区、裁剪、编辑器背景全程复用同一张图。旧版每次截图要做
/// 3 次全屏 captureImage + 4 次 SCShareableContent 枚举，是卡顿的主因。
final class ScreenCaptureService: Sendable {
    /// 从已冻结的全屏图里裁出选区（同步、无 IPC、无抓图）。
    ///
    /// 像素坐标换算沿用旧版 captureRegion 的同一套数学（`cropping(to:)` 的
    /// y 与 AppKit 全局坐标同向，不翻转），不要“修正”它。
    func cropRegion(
        _ rect: CGRect,
        displayID: CGDirectDisplayID,
        displayFrame: CGRect,
        frozenImage: CGImage
    ) throws -> RegionCaptureResult {
        guard rect.width >= 1, rect.height >= 1 else { throw CaptureError.emptyRegion }

        // 像素坐标 = (逻辑坐标 - 显示器原点) × 像素密度
        // 截图实际尺寸 vs 显示器点尺寸 推断 scale（SCDisplay 无 scale 属性）
        let scaleX = CGFloat(frozenImage.width) / displayFrame.width
        let scaleY = CGFloat(frozenImage.height) / displayFrame.height
        let pxRect = CGRect(
            x: (rect.origin.x - displayFrame.origin.x) * scaleX,
            y: (rect.origin.y - displayFrame.origin.y) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral

        guard let cropped = frozenImage.cropping(to: pxRect), cropped.width > 0, cropped.height > 0 else {
            throw CaptureError.cropFailed
        }
        return RegionCaptureResult(image: cropped, rect: rect, displayID: displayID)
    }
}
