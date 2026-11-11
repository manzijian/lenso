import SwiftUI

/// 颜色令牌。Apple 设计风格 + 经典克莱因蓝（International Klein Blue）高对比白底搭配。
enum LensoColors {
    /// 经典克莱因蓝（International Klein Blue / IKB #002FA7，纯粹、浓郁、科技与艺术感）
    static let kleinBlue = Color(red: 0.00, green: 0.184, blue: 0.655)

    /// 鲜亮电光克莱因蓝（用于高亮态、选中徽标与核心主按钮）
    static let kleinBlueBright = Color(red: 0.02, green: 0.22, blue: 0.88)

    /// 极浅克莱因蓝底色（用于选中项背景、悬停胶囊等）
    static let kleinBlueSoft = Color(red: 0.02, green: 0.22, blue: 0.88).opacity(0.08)

    /// 主强调色（使用克莱因蓝）
    static let accent = kleinBlueBright

    /// 渐变氛围 — 克莱因蓝微光微透，极简 Apple 原生感，不滥用渐变
    static let accentGradient = LinearGradient(
        colors: [
            kleinBlueBright,
            Color(red: 0.00, green: 0.28, blue: 0.95),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    /// 选中描边（克莱因蓝高光光环）
    static let selectionRing = kleinBlueBright

    /// 危险操作（直接永久删除）
    static let danger = Color(red: 0.92, green: 0.24, blue: 0.24)
}
