import AppKit
import CoreGraphics
import OSLog

let selLog = Logger(subsystem: "com.lenso.app", category: "capture")

// MARK: - 拖拽状态机与手柄数学

/// 选区拖拽模式
enum SelectorDragMode {
    case creating
    case moving(original: CGRect)
    case resizing(handle: SelectorResizeHandle, original: CGRect)
}

/// 选区 8 手柄
enum SelectorResizeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .top: CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func hitRect(in rect: CGRect, tolerance: CGFloat) -> CGRect {
        let diameter = tolerance * 2
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            let point = point(in: rect)
            return CGRect(x: point.x - tolerance, y: point.y - tolerance, width: diameter, height: diameter)
        case .top:
            return CGRect(x: rect.minX + tolerance, y: rect.maxY - tolerance, width: max(0, rect.width - diameter), height: diameter)
        case .right:
            return CGRect(x: rect.maxX - tolerance, y: rect.minY + tolerance, width: diameter, height: max(0, rect.height - diameter))
        case .bottom:
            return CGRect(x: rect.minX + tolerance, y: rect.minY - tolerance, width: max(0, rect.width - diameter), height: diameter)
        case .left:
            return CGRect(x: rect.minX - tolerance, y: rect.minY + tolerance, width: diameter, height: max(0, rect.height - diameter))
        }
    }

    var cursor: NSCursor {
        NSCursor.frameResize(position: frameResizePosition, directions: .all)
    }

    private var frameResizePosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        }
    }
}

enum SelectorRectEditor {
    static let resizeHitTolerance: CGFloat = 10

    static func resizeHandle(at point: CGPoint, for rect: CGRect, tolerance: CGFloat = resizeHitTolerance) -> SelectorResizeHandle? {
        let corners: [SelectorResizeHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        if let corner = corners.first(where: { $0.hitRect(in: rect, tolerance: tolerance).contains(point) }) {
            return corner
        }
        let edges: [SelectorResizeHandle] = [.top, .right, .bottom, .left]
        return edges.first(where: { $0.hitRect(in: rect, tolerance: tolerance).contains(point) })
    }

    static func moved(_ rect: CGRect, by offset: CGPoint, inside bounds: CGRect) -> CGRect {
        let x = min(max(bounds.minX, rect.minX + offset.x), bounds.maxX - rect.width)
        let y = min(max(bounds.minY, rect.minY + offset.y), bounds.maxY - rect.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: rect.size).integral
    }

    static func resized(_ rect: CGRect, handle: SelectorResizeHandle, to point: CGPoint, inside bounds: CGRect) -> CGRect {
        let point = CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
        let x1: CGFloat
        let x2: CGFloat
        let y1: CGFloat
        let y2: CGFloat
        switch handle {
        case .topLeft: (x1, x2, y1, y2) = (point.x, rect.maxX, rect.minY, point.y)
        case .top: (x1, x2, y1, y2) = (rect.minX, rect.maxX, rect.minY, point.y)
        case .topRight: (x1, x2, y1, y2) = (rect.minX, point.x, rect.minY, point.y)
        case .right: (x1, x2, y1, y2) = (rect.minX, point.x, rect.minY, rect.maxY)
        case .bottomRight: (x1, x2, y1, y2) = (rect.minX, point.x, point.y, rect.maxY)
        case .bottom: (x1, x2, y1, y2) = (rect.minX, rect.maxX, point.y, rect.maxY)
        case .bottomLeft: (x1, x2, y1, y2) = (point.x, rect.maxX, point.y, rect.maxY)
        case .left: (x1, x2, y1, y2) = (point.x, rect.maxX, rect.minY, rect.maxY)
        }
        return CGRect(
            x: min(x1, x2), y: min(y1, y2),
            width: abs(x2 - x1), height: abs(y2 - y1)
        ).intersection(bounds).integral
    }
}

// MARK: - 单显示器覆盖面板

/// 面板容器：用 cursor rect 注册自绘十字光标。
/// 只靠 mouseMoved 里 set() 会被系统的光标管理覆盖，cursor rect 才是可靠入口。
final class CursorContainerView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: LensoCursor.crosshair)
    }
}

/// 单显示器覆盖面板：透明，选区里直接透出实时桌面 + 暗幕，选区挖空，Esc 取消。
final class RegionSelectorPanel: NSPanel {
    private weak var controller: RegionSelectorController?
    private let sizeLabel: NSTextField
    private let frozenView: NSImageView
    private let dimSelectionView: SelectionView
    private let colorBadge = PixelColorBadgeView()
    private var handlesVisible = false
    let screenFrame: CGRect
    let ownDisplayID: CGDirectDisplayID

    init(screen: NSScreen, controller: RegionSelectorController) {
        self.controller = controller
        self.screenFrame = screen.frame
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
            ?? 0
        self.ownDisplayID = displayID
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.isHidden = true
        self.sizeLabel = label
        let frozen = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        frozen.imageScaling = .scaleAxesIndependently
        frozen.autoresizingMask = [.width, .height]
        frozen.isHidden = true
        self.frozenView = frozen
        self.dimSelectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame)
        dimSelectionView.autoresizingMask = [.width, .height]
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.becomesKeyOnlyIfNeeded = false
        self.worksWhenModal = true

        let container = CursorContainerView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(frozenView)
        container.addSubview(dimSelectionView)
        container.addSubview(sizeLabel)
        container.addSubview(colorBadge)
        self.contentView = container
        self.setFrame(screen.frame, display: false)
        selLog.info("panel init screen=\(NSStringFromRect(screen.frame), privacy: .public) frame=\(NSStringFromRect(self.frame), privacy: .public)")
    }

    var screenFrameForDisplay: CGRect { screenFrame }

    /// 冻结帧到位后铺上（抓图是异步的，通常几十毫秒后到）
    func setFrozenImage(_ image: CGImage) {
        frozenView.image = NSImage(cgImage: image, size: screenFrame.size)
        frozenView.isHidden = false
        colorBadge.setFrozenImage(image)
    }

    override var canBecomeKey: Bool { true }

    func drawHoverHighlight(_ globalRect: CGRect?) {
        dimSelectionView.hoverFrame = globalRect
    }

    func drawSelection(_ globalRect: CGRect?) {
        dimSelectionView.selection = globalRect ?? .zero
        guard let globalRect else {
            sizeLabel.isHidden = true
            return
        }
        let x = Int(globalRect.minX - screenFrame.origin.x)
        let yFromTop = Int(screenFrame.maxY - globalRect.maxY)
        sizeLabel.stringValue = "\(x), \(yFromTop) · \(Int(globalRect.width)) × \(Int(globalRect.height))"
        sizeLabel.frame.origin = CGPoint(
            x: globalRect.origin.x - screenFrame.origin.x + 8,
            y: screenFrame.height - (globalRect.origin.y - screenFrame.origin.y) - 28
        )
        sizeLabel.isHidden = false
    }

    func setHandlesVisible(_ visible: Bool) {
        handlesVisible = visible
        dimSelectionView.showsHandles = visible
        if visible { colorBadge.hide() }
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.cancel()
    }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        controller?.mouseDown(at: NSEvent.mouseLocation, panel: self)
        updateColorBadge(atWindowPoint: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        controller?.mouseDragged(to: location)
        updateColorBadge(atWindowPoint: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        controller?.mouseMovedOrHovered(at: location)
        controller?.cursor(at: location).set()
        if handlesVisible {
            colorBadge.hide()
        } else {
            updateColorBadge(atWindowPoint: event.locationInWindow)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 {
            controller?.doubleClick(at: NSEvent.mouseLocation)
            return
        }
        controller?.mouseUp(at: NSEvent.mouseLocation)
        colorBadge.hide()
    }

    /// 光标在窗口内的位置 → 面板坐标，驱动色值提示跟随
    private func updateColorBadge(atWindowPoint point: CGPoint) {
        guard let container = contentView else { return }
        let local = container.convert(point, from: nil)
        colorBadge.update(cursor: local, panelSize: container.bounds.size)
    }
}

// MARK: - 暗幕与选区

/// 选区视图：不压暗屏幕，只在选区上画蓝色描边、悬停窗口高亮、选区 8 手柄。
private final class SelectionView: NSView {
    private let borderLayer = CAShapeLayer()
    private let hoverBorderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()

    let screenFrame: CGRect

    init(frame: NSRect, screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(frame: frame)
        wantsLayer = true
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor(red: 5/255, green: 56/255, blue: 224/255, alpha: 0.9).cgColor
        borderLayer.lineWidth = 1.5
        hoverBorderLayer.fillColor = NSColor.clear.cgColor
        hoverBorderLayer.strokeColor = NSColor(red: 5/255, green: 56/255, blue: 224/255, alpha: 0.85).cgColor
        hoverBorderLayer.lineWidth = 2
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor(red: 5/255, green: 56/255, blue: 224/255, alpha: 1).cgColor
        handlesLayer.lineWidth = 1.5
        layer?.addSublayer(borderLayer)
        layer?.addSublayer(hoverBorderLayer)
        layer?.addSublayer(handlesLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func localRect(_ global: CGRect) -> CGRect {
        CGRect(
            x: global.minX - screenFrame.minX,
            y: global.minY - screenFrame.minY,
            width: global.width,
            height: global.height
        )
    }

    var selection: CGRect = .zero {
        didSet { layoutLayers() }
    }
    var hoverFrame: CGRect? = nil {
        didSet { layoutLayers() }
    }
    var showsHandles = false {
        didSet { layoutLayers() }
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if selection.width > 0 {
            let local = localRect(selection)
            borderLayer.path = CGPath(rect: local.insetBy(dx: 0.5, dy: 0.5), transform: nil)
            borderLayer.frame = bounds
            borderLayer.isHidden = false
        } else {
            borderLayer.isHidden = true
        }

        if let hover = hoverFrame, selection.width == 0 {
            let localHover = localRect(hover).intersection(bounds)
            if !localHover.isEmpty {
                hoverBorderLayer.path = CGPath(rect: localHover.insetBy(dx: 1, dy: 1), transform: nil)
                hoverBorderLayer.frame = bounds
                hoverBorderLayer.isHidden = false
            } else {
                hoverBorderLayer.isHidden = true
            }
        } else {
            hoverBorderLayer.isHidden = true
        }

        if showsHandles, selection.width > 0 {
            let local = localRect(selection)
            let handlePath = CGMutablePath()
            for handle in SelectorResizeHandle.allCases {
                let point = handle.point(in: local)
                handlePath.addRect(CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
            }
            handlesLayer.path = handlePath
            handlesLayer.frame = bounds
            handlesLayer.isHidden = false
        } else {
            handlesLayer.isHidden = true
        }
    }
}
