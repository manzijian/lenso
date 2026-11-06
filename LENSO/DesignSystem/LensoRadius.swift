import CoreGraphics

/// 圆角令牌 — 精致统一，窗口 > 卡片 > 控件。
enum LensoRadius {
    /// 窗口内容容器
    static let window: CGFloat = 16
    /// 浮动面板（操作条、搜索结果卡）
    static let panel: CGFloat = 14
    /// 图片缩略图
    static let thumbnail: CGFloat = 10
    /// 小控件（按钮、输入框）
    static let control: CGFloat = 8
    /// 胶囊
    static let capsule: CGFloat = 999
}
