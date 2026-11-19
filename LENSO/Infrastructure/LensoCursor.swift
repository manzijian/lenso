import AppKit
import SwiftUI

/// 截图专用光标：细十字 + 中心留空，比系统 NSCursor.crosshair 更细、更精准。
/// 用黑色粗线打底 + 白色细线覆盖，深浅背景上都能看清。
@MainActor
enum LensoCursor {
    static let crosshair: NSCursor = makeCrosshair()

    private static func makeCrosshair() -> NSCursor {
        // 奇数边长，保证热点正好落在中心像素上
        let side: CGFloat = 25
        let arm: CGFloat = 7.5
        let gap: CGFloat = 3.5

        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let center = NSPoint(x: side / 2, y: side / 2)
            let path = NSBezierPath()

            path.move(to: NSPoint(x: center.x, y: center.y + gap))
            path.line(to: NSPoint(x: center.x, y: center.y + arm))
            path.move(to: NSPoint(x: center.x, y: center.y - gap))
            path.line(to: NSPoint(x: center.x, y: center.y - arm))
            path.move(to: NSPoint(x: center.x + gap, y: center.y))
            path.line(to: NSPoint(x: center.x + arm, y: center.y))
            path.move(to: NSPoint(x: center.x - gap, y: center.y))
            path.line(to: NSPoint(x: center.x - arm, y: center.y))

            // 黑色描边打底
            NSColor.black.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 3.5
            path.stroke()

            // 白色细线
            NSColor.white.setStroke()
            path.lineWidth = 1.4
            path.stroke()

            // 中心品牌色定位点（外面一圈白色衬底，深浅背景都清楚）
            let radius: CGFloat = 1.9
            let dotRect = NSRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            )
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -0.8, dy: -0.8)).fill()
            NSColor(red: 5 / 255, green: 56 / 255, blue: 224 / 255, alpha: 1).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }

        return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
    }
}

// MARK: - SwiftUI 里注册 AppKit 光标区域

extension View {
    /// 在 SwiftUI 视图上注册系统光标区域。
    /// 光标由 AppKit 管理，拖动、窗口刷新后都不会被重置成箭头；同时不拦截鼠标事件。
    func cursorRect(_ cursor: NSCursor) -> some View {
        background(CursorRectRepresentable(cursor: cursor))
    }
}

private struct CursorRectRepresentable: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectView {
        CursorRectView(cursor: cursor)
    }

    func updateNSView(_ view: CursorRectView, context: Context) {
        view.cursor = cursor
        view.window?.invalidateCursorRects(for: view)
    }
}

final class CursorRectView: NSView {
    var cursor: NSCursor

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    /// 只负责光标，不参与点击/拖拽事件
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
