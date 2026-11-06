import ScreenCaptureKit
import CoreGraphics

enum CapturePermissionStatus {
    case authorized
    case denied
    case notDetermined
}

/// 屏幕录制权限检查（规范 11.2：渐进式权限，首次截图时申请）
enum CapturePermissionService {
    static func currentStatus() -> CapturePermissionStatus {
        CGPreflightScreenCaptureAccess() ? .authorized : .denied
    }

    /// 触发系统授权弹窗，并返回最新状态（需要用户在系统设置中授权后重试）
    static func requestAccess() async -> CapturePermissionStatus {
        _ = CGRequestScreenCaptureAccess()
        // 弹窗是异步的：等一小段时间后再查
        try? await Task.sleep(for: .seconds(1))
        return currentStatus()
    }
}
