import SwiftUI

/// 颜色令牌。蓝紫系柔和氛围；图片区域保持中性，不上色。
enum LensoColors {
    /// 主强调色 — 蓝（系统蓝基准，略偏紫以呼应玻璃氛围）
    static let accent = Color(red: 0.28, green: 0.46, blue: 1.00)

    /// 渐变氛围 — 蓝到紫，仅用于背景光晕与选中态，不用于正文
    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.28, green: 0.46, blue: 1.00),
            Color(red: 0.62, green: 0.44, blue: 1.00),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    /// 选中描边
    static let selectionRing = Color.white.opacity(0.9)

    /// 危险操作（删除）
    static let danger = Color.red
}
