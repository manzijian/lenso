import SwiftUI

/// 材质令牌 — macOS 26 Liquid Glass 优先，原生 material 兜底。
/// 规则：玻璃只用于悬浮层（工具栏、操作条、面板）；图片和正文区域保持清晰。
/// glassEffect 是 View 修饰符而非 ShapeStyle，因此这里提供的是 View 包装。
enum LensoMaterials {
    /// 悬浮工具栏 / 操作条 — 正规玻璃胶囊
    static func glassToolbar(_ content: some View) -> some View {
        content.glassEffect(.regular, in: Capsule())
    }

    /// 浮动面板 — 正规玻璃圆角矩形
    static func glassPanel(_ content: some View) -> some View {
        content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: LensoRadius.panel))
    }

    /// 需要组合多个玻璃元素时使用（防玻璃叠加发灰）
    @MainActor
    static func glassContainer(@ViewBuilder content: () -> some View) -> some View {
        GlassEffectContainer(spacing: LensoSpacing.s) {
            content()
        }
    }

    /// 不支持 glassEffect 的兜底材质
    static let fallbackMaterial: Material = .ultraThinMaterial
}
