import AppKit
import SwiftUI

/// 把面板装进一个自己管理的 NSView 里。
/// 外层容器铺满整个画面，面板本体在内层随意移动；
/// 拖动只改内层视图的 frame，不经过 SwiftUI 布局，也没有坐标变换，方向和距离都精确。
struct LayerHostedPanel: NSViewRepresentable {
    let content: AnyView
    let panelSize: CGSize
    /// 面板左上角在编辑器内的位置（左上为原点）
    let origin: CGPoint

    func makeNSView(context: Context) -> PanelDragContainer {
        let container = PanelDragContainer()
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: .aqua)
        container.install(hostingView: host, panelSize: panelSize, origin: origin)
        return container
    }

    func updateNSView(_ view: PanelDragContainer, context: Context) {
        view.hostingView?.rootView = content
        view.updateDefaultOrigin(origin)
    }
}

/// 铺满画面的容器：只负责托管面板与拖拽，不在面板范围外拦截事件
final class PanelDragContainer: NSView {
    private(set) var hostingView: NSHostingView<AnyView>?
    private var movable: FlippedView?
    private var strip: PanelDragStrip?
    private var panelSize: CGSize = .zero
    private var defaultOrigin: CGPoint = .zero
    private var userMoved = false

    override var isFlipped: Bool { true }

    func install(hostingView: NSHostingView<AnyView>, panelSize: CGSize, origin: CGPoint) {
        wantsLayer = true
        layer?.masksToBounds = false
        self.panelSize = panelSize
        self.defaultOrigin = origin

        // 内层容器由我们自己摆：拖动时只改它的 frame
        let movable = FlippedView(frame: NSRect(origin: origin, size: panelSize))
        movable.addSubview(hostingView)
        hostingView.frame = movable.bounds
        hostingView.autoresizingMask = [.width, .height]

        let strip = PanelDragStrip()
        strip.onDrag = { [weak self] dx, dy in
            self?.move(dx: dx, dy: dy)
        }
        movable.addSubview(strip)

        addSubview(movable)
        self.movable = movable
        self.hostingView = hostingView
        self.strip = strip
    }

    /// 布局给的默认位置变化时同步（用户拖动过就不再回位）
    func updateDefaultOrigin(_ origin: CGPoint) {
        defaultOrigin = origin
        guard !userMoved else { return }
        movable?.frame.origin = origin
    }

    override func layout() {
        super.layout()
        movable?.frame.size = panelSize
        hostingView?.frame = movable?.bounds ?? .zero
        // 顶部 26pt 作为拖动带（面板里这块只放抓手，不放按钮）
        strip?.frame = NSRect(x: 0, y: 0, width: panelSize.width, height: 26)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let movable else { return nil }
        let local = convert(point, to: movable)
        guard movable.bounds.contains(local) else { return nil }

        if let strip, strip.frame.contains(local) {
            return strip
        }
        return super.hitTest(point)
    }

    private func move(dx: CGFloat, dy: CGFloat) {
        guard let movable else { return }
        movable.frame.origin.x += dx
        movable.frame.origin.y += dy
        userMoved = true
    }
}

/// 翻转坐标系的内层视图：原点在左上，y 向下，和拖动方向一致
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 透明拖动带：把鼠标位移换算到父视图坐标系后交给容器
private final class PanelDragStrip: NSView {
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    private var lastPoint: NSPoint?

    override func mouseDown(with event: NSEvent) {
        lastPoint = superview?.convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastPoint, let parent = superview else { return }
        let point = parent.convert(event.locationInWindow, from: nil)
        onDrag?(point.x - last.x, point.y - last.y)
        lastPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        lastPoint = nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
