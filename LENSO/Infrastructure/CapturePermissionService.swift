import ScreenCaptureKit
import CoreGraphics

enum CapturePermissionStatus {
    case authorized
    case denied
    case notDetermined
}

/// 屏幕录制权限（macOS TCC）
///
/// 注意：`CGPreflightScreenCaptureAccess()` 在 macOS 26 上对 ad-hoc 签名的调试构建
/// 可能持续返回 false（即使系统设置里开关已打开），而 ScreenCaptureKit 实际可用。
/// 因此以「能否真正枚举可共享内容」为准，preflight 仅作参考。
enum CapturePermissionService {
    static func currentStatus() -> CapturePermissionStatus {
        CGPreflightScreenCaptureAccess() ? .authorized : .notDetermined
    }

    /// 真实能力探测：能枚举屏幕内容即视为已授权
    static func probeAccess() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    /// 请求授权（触发系统弹窗）并等待首次探测
    static func requestAccess() async -> CapturePermissionStatus {
        _ = CGRequestScreenCaptureAccess()
        try? await Task.sleep(for: .seconds(1))
        return await probeAccess() ? .authorized : .denied
    }
}
