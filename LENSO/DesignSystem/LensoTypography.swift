import SwiftUI

/// 字体令牌 — 全部基于系统字体（SF Pro / PingFang SC），保证原生感。
enum LensoTypography {
    static let largeTitle = Font.system(size: 26, weight: .bold)
    static let title = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let callout = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11, weight: .regular)
    /// 数字角标（选中计数）
    static let badge = Font.system(size: 10, weight: .semibold, design: .rounded)
}
