import SwiftUI

/// 阴影令牌 — 柔和环境光感，禁止生硬重阴影。
enum LensoShadows {
    /// 浮动面板（操作条、悬浮工具栏）
    static func panel<S: Shape>(_ shadow: S) -> some View {
        shadow
            .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    /// 窗口内卡片
    static func card<S: Shape>(_ shadow: S) -> some View {
        shadow.shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }
}
