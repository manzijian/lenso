import AppKit
import SwiftUI

/// 统一动效语言 — 苹果级克制、丝滑、可打断且尊重「减少动态效果」。
enum LensoAnimations {
    /// 开关、分段选择、工具激活、标签切换
    static let snappy = Animation.spring(response: 0.22, dampingFraction: 0.86)
    /// 悬停与按压微反馈
    static let hover = Animation.spring(response: 0.20, dampingFraction: 0.84)
    /// 面板、抽屉、浮层出现/收起
    static let panel = Animation.spring(response: 0.30, dampingFraction: 0.86)
    /// 列表交错入场、图表柱状增长
    static let gentle = Animation.spring(response: 0.38, dampingFraction: 0.88)
    /// 纯透明度过渡（亦作「减少动态效果」降级曲线）
    static let fade = Animation.easeOut(duration: 0.15)
    /// 极短微过渡
    static let quickFade = Animation.easeOut(duration: 0.10)

    /// 根据系统「减少动态效果」设置返回合适的动画曲线
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    /// 统一的 `withAnimation` 封装，自动尊重「减少动态效果」
    @MainActor
    static func withMotion(
        _ animation: Animation = snappy,
        reduceMotion: Bool? = nil,
        _ body: () -> Void
    ) {
        let shouldReduce = reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(resolve(animation, reduceMotion: shouldReduce), body)
    }
}

/// 统一转场预设 — 明确交代「从哪来、到哪去」
enum LensoTransitions {
    /// 条件设置行 / 替换栏等向下展开内容
    static func inlineExpand(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    /// 底部工具参数栏向上展开
    static func bottomExpand(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    /// 状态徽章 / 复制确认 / 警告提示
    static func badge(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.90))
    }

    /// 轻量化模态 / 预览卡片
    static func overlayCard(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .scale(scale: 0.98).combined(with: .opacity)
        )
    }
}

/// 统一按压反馈样式 — 按下去有明确回应，松手自然回弹
struct LensoPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var pressedOpacity: Double = 0.88
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(LensoAnimations.resolve(LensoAnimations.hover, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension View {
    /// 图标切换（如 复制 → 勾选、星标状态切换）
    func lensoSymbolReplace() -> some View {
        contentTransition(.symbolEffect(.replace))
    }

    /// 数字变化（如 计数、缩放百分比、匹配数量）
    func lensoNumericTransition() -> some View {
        contentTransition(.numericText())
    }

    /// 自动尊重「减少动态效果」的 `.animation` 修饰器
    func lensoAnimation<V: Equatable>(_ animation: Animation, value: V, reduceMotion: Bool) -> some View {
        self.animation(LensoAnimations.resolve(animation, reduceMotion: reduceMotion), value: value)
    }
}

/// AppKit 窗口 / 面板统一入退场动效
@MainActor
enum LensoWindowMotion {
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
    static let easeIn = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func present(
        _ window: NSWindow,
        duration: TimeInterval = 0.16,
        slideY: CGFloat = 0,
        makeKey: Bool = false
    ) {
        let reduced = reduceMotion
        let targetFrame = window.frame
        if !reduced && slideY != 0 {
            var startFrame = targetFrame
            startFrame.origin.y -= slideY
            window.setFrame(startFrame, display: false)
        }
        window.alphaValue = 0
        if window.styleMask.contains(.nonactivatingPanel) {
            window.orderFrontRegardless()
            if makeKey {
                window.makeKey()
            }
        } else if makeKey {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduced ? min(duration, 0.10) : duration
            ctx.timingFunction = easeOut
            ctx.allowsImplicitAnimation = true
            window.animator().alphaValue = 1
            if !reduced && slideY != 0 {
                window.animator().setFrame(targetFrame, display: true)
            }
        }
    }

    static func dismiss(
        _ window: NSWindow,
        duration: TimeInterval = 0.12,
        slideY: CGFloat = 0,
        completion: (@MainActor () -> Void)? = nil
    ) {
        let reduced = reduceMotion
        let originFrame = window.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduced ? min(duration, 0.08) : duration
            ctx.timingFunction = easeIn
            ctx.allowsImplicitAnimation = true
            window.animator().alphaValue = 0
            if !reduced && slideY != 0 {
                var endFrame = originFrame
                endFrame.origin.y -= slideY
                window.animator().setFrame(endFrame, display: true)
            }
        }, completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
                window.alphaValue = 1
                if !reduced && slideY != 0 {
                    window.setFrame(originFrame, display: false)
                }
                completion?()
            }
        })
    }
}
