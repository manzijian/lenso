import SwiftUI

/// 动画令牌 — 自然、克制。响应式动画（hover/选中）用短弹簧；出现动画用缓动。
enum LensoAnimations {
    /// 悬停与选中反馈
    static let hover = Animation.spring(response: 0.25, dampingFraction: 0.8)
    /// 面板出现/消失
    static let panel = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// 快速透明度
    static let fade = Animation.easeOut(duration: 0.15)
}
