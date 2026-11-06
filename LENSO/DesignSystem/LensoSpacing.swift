import CoreGraphics

/// 间距令牌，4pt 基准网格。
enum LensoSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// 侧边窄导航栏宽度
    static let sidebarWidth: CGFloat = 64
    /// 工具栏高度
    static let toolbarHeight: CGFloat = 48
    /// 底部浮动操作条高度
    static let actionBarHeight: CGFloat = 52
    /// 窗口内容最小留白
    static let windowPadding: CGFloat = 16
}
