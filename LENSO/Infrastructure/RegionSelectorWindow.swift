import AppKit
import CoreGraphics
import OSLog

private let selLog = Logger(subsystem: "com.lenso.app", category: "capture")

/// 跨屏选区覆盖窗口控制器（规范 2.2：窗口精确控制走 AppKit）
///
/// 丝滑修复后的流程：coordinator 先抓一张冻结图、再上屏；选区、裁剪、编辑器
/// 全程复用同一张图。选区面板出现时图已就位，不再先上屏后异步冻结。
@MainActor
final class RegionSelectorController: NSObject {
    private var panels: [RegionSelectorPanel] = []
    private var onComplete: ((CGRect, CGDirectDisplayID) -> Void)?
    private var origin: CGPoint?
    /// 记录 mouseDown 所在的 panel，mouseUp 据此确定显示器
    private weak var downPanel: RegionSelectorPanel?
    /// 可吸附的窗口列表（Z 轴序，layer 0）
    private var snappableWindows: [(windowID: CGWindowID, frame: CGRect, title: String)] = []
    /// 当前悬停吸附的窗口
    private var hoverWindowFrame: CGRect?
    /// 是否已被关闭（供 coordinator 在回调 Task 里判断用户是否已 Esc 取消）
    private(set) var isDismissed = false

    /// 开始选区。冻结图由 coordinator 预抓，面板出现时图已就位（先冻结、后上屏）。
    func begin(frozenFrames: [CGDirectDisplayID: CGImage], onComplete: @escaping (CGRect, CGDirectDisplayID) -> Void) {
        // 关闭可能残留的旧面板（泄漏防护）
        end()
        isDismissed = false
        self.onComplete = onComplete
        self.origin = nil
        panels = NSScreen.screens.map { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
            return RegionSelectorPanel(screen: screen, frozenImage: frozenFrames[displayID], controller: self)
        }
        // orderFrontRegardless 绕过 App 激活状态限制，保证 screenSaver 层级面板上屏
        for panel in panels {
            panel.setFrame(panel.screenFrameForDisplay, display: true)
            panel.orderFrontRegardless()
        }
        panels.first?.makeKey()
        NSCursor.crosshair.set()
        snappableWindows = Self.loadSnappableWindows()
        selLog.info("snappable windows: \(self.snappableWindows.count)")
    }

    /// Snapzy 方案：CGWindowList 取 Z 轴序 layer 0 窗口，无权限依赖
    static func loadSnappableWindows() -> [(windowID: CGWindowID, frame: CGRect, title: String)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        // 屏幕全局最大 Y（CG 坐标左上原点 ↔ AppKit 左下原点转换基准）
        let globalMaxY = NSScreen.screens.map(\.frame).map(\.maxY).max() ?? 0
        var result: [(CGWindowID, CGRect, String)] = []
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = boundsDict["Width"], let height = boundsDict["Height"],
                  width > 32, height > 32,
                  let alpha = w[kCGWindowAlpha as String] as? CGFloat, alpha > 0,
                  let windowID = w[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            let x = boundsDict["X"] ?? 0
            let yTop = boundsDict["Y"] ?? 0
            // CGWindowBounds：全局左上原点 → AppKit 全局左下原点
            let appKitY = globalMaxY - yTop - height
            let frame = CGRect(x: x, y: appKitY, width: width, height: height)
            let title = w[kCGWindowName as String] as? String ?? ""
            result.append((windowID, frame.integral, title))
        }
        return result
    }

    /// 命中测试：返回鼠标所在的最顶层可吸附窗口
    func hitTestWindow(at globalPoint: CGPoint) -> CGRect? {
        // CGWindowList 全局坐标（左上原点）；AppKit 全局坐标（左下原点）
        // loadSnappableWindows 已转换；命中时用全局 AppKit 坐标
        snappableWindows.first(where: { $0.frame.contains(globalPoint) })?.frame
    }

    func mouseMovedOrHovered(at globalPoint: CGPoint) {
        // 悬停吸附高亮（未按下时）
        guard origin == nil else { return }
        let hit = hitTestWindow(at: globalPoint)
        if hit != hoverWindowFrame {
            hoverWindowFrame = hit
            panels.forEach { $0.drawHoverHighlight(hit) }
        }
    }

    func mouseDown(at globalPoint: CGPoint, panel: RegionSelectorPanel) {
        origin = globalPoint
        downPanel = panel
        selLog.info("selector mouseDown at \(NSStringFromPoint(globalPoint), privacy: .public)")
    }

    /// 供 panel 判断单击/拖拽（不暴露 origin 写权限）
    var currentOriginInternal: CGPoint? { origin }

    func mouseDragged(to globalPoint: CGPoint) {
        guard origin != nil else { return }
        let rect = snapRect(rectBetween(origin ?? .zero, globalPoint))
        hoverWindowFrame = nil
        panels.forEach {
            $0.drawHoverHighlight(nil)
            $0.drawSelection(rect)
        }
    }

    func mouseUp(at globalPoint: CGPoint) {
        guard let origin else { return }
        let rect = snapRect(rectBetween(origin, globalPoint))
        self.origin = nil
        selLog.info("selector mouseUp rect=\(NSStringFromRect(rect), privacy: .public)")
        // 矩形太小视为误触：直接关闭，不回调
        guard rect.width >= 8, rect.height >= 8 else {
            end()
            return
        }
        // 不在这里 end()：编辑器先上、选区面板后关，中间不露桌面。
        // 关闭由 coordinator 在编辑器上屏后调用 dismiss()。
        let callback = onComplete
        let downPanelRef = downPanel
        guard let callback else { return }
        // 用 mouseDown 时的 panel 所在显示器；拿不到再按坐标匹配
        let displayID: CGDirectDisplayID?
        if let downPanelRef {
            displayID = downPanelRef.ownDisplayID
        } else {
            displayID = NSScreen.screens.first(where: { NSMouseInRect(globalPoint, $0.frame, false) })
                .map { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID }
        }
        if let displayID {
            selLog.info("onComplete display=\(displayID)")
            callback(rect, displayID)
        } else {
            selLog.error("no display matched for \(NSStringFromPoint(globalPoint), privacy: .public)")
            end()
        }
    }

    /// 窗口吸附：单击（按下和松开几乎同点）时选定悬停窗口
    func clickAt(globalPoint: CGPoint) {
        if let hit = hitTestWindow(at: globalPoint) {
            selLog.info("window snap click at \(NSStringFromPoint(globalPoint), privacy: .public)")
            let callback = onComplete
            let downPanelRef = downPanel
            guard let callback else { return }
            let displayID = downPanelRef?.ownDisplayID
                ?? NSScreen.screens.first(where: { NSMouseInRect(globalPoint, $0.frame, false) })
                    .map { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID }
            if let displayID {
                callback(hit, displayID)
            } else {
                end()
            }
        }
        // 悬停处没有窗口：什么都不做，选区保持打开（旧行为）
    }

    /// 供 coordinator 在编辑器上屏后调用：关选区面板（不触发回调）
    func dismiss() {
        end()
    }

    func cancel() {
        selLog.info("selector cancelled")
        end()
    }

    /// 拖拽时边缘吸附：选区边贴近窗口边（8pt 内）自动贴合（Snipaste 同款行为）
    private func snapRect(_ rect: CGRect) -> CGRect {
        let threshold: CGFloat = 8
        var r = rect
        for f in snappableWindows.map(\.frame) {
            if abs(r.minX - f.minX) <= threshold {
                r.size.width += r.minX - f.minX
                r.origin.x = f.minX
            }
            if abs(r.maxX - f.maxX) <= threshold {
                r.size.width = f.maxX - r.minX
            }
            if abs(r.minY - f.minY) <= threshold {
                r.size.height += r.minY - f.minY
                r.origin.y = f.minY
            }
            if abs(r.maxY - f.maxY) <= threshold {
                r.size.height = f.maxY - r.minY
            }
        }
        return r.integral
    }

    private func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(a.x - b.x), height: abs(a.y - b.y)
        ).integral
    }

    private func end() {
        isDismissed = true
        panels.forEach { $0.orderOut(nil) }
        panels.forEach { $0.close() }
        panels.removeAll()
        downPanel = nil
        hoverWindowFrame = nil
        onComplete = nil
        NSCursor.arrow.set()
    }
}

/// 单显示器覆盖面板：冻结屏幕截图为背景 + 暗幕，选区挖空，Esc 取消
final class RegionSelectorPanel: NSPanel {
    private weak var controller: RegionSelectorController?
    private var selection: CGRect = .zero // 全局坐标
    private let screenFrame: CGRect
    private let sizeLabel: NSTextField
    private let frozenImageView: NSImageView
    private let dimSelectionView: SelectionView
    private let crosshairView: CrosshairView
    private let magnifierView: MagnifierView
    let ownDisplayID: CGDirectDisplayID

    init(screen: NSScreen, frozenImage: CGImage?, controller: RegionSelectorController) {
        self.controller = controller
        self.screenFrame = screen.frame
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        self.ownDisplayID = displayID
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.isHidden = true
        label.tag = Int(displayID)
        self.sizeLabel = label
        self.frozenImageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        frozenImageView.autoresizingMask = [.width, .height]
        // 冻结图已预抓，上屏时直接就位，不再异步抓（旧 freezeScreen 已删）
        if let frozenImage {
            frozenImageView.image = NSImage(cgImage: frozenImage, size: screen.frame.size)
        }
        // 暗幕+选区绘制层（叠在冻结图上方）
        self.dimSelectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        dimSelectionView.autoresizingMask = [.width, .height]
        self.crosshairView = CrosshairView(frame: NSRect(origin: .zero, size: screen.frame.size))
        crosshairView.autoresizingMask = [.width, .height]
        self.magnifierView = MagnifierView(frozenImage: frozenImage, displayFrame: screen.frame)
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

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(frozenImageView)
        // 暗幕+选区层必须叠在冻结图之上，否则挖空/边框全被遮住
        container.addSubview(dimSelectionView)
        container.addSubview(crosshairView)
        container.addSubview(magnifierView)
        container.addSubview(sizeLabel)
        self.contentView = container
        // 显式设置 frame：borderless NSPanel 的 contentRect 初始化有时不生效
        self.setFrame(screen.frame, display: false)
        selLog.info("panel init screen=\(NSStringFromRect(screen.frame), privacy: .public) frame=\(NSStringFromRect(self.frame), privacy: .public)")
    }

    var screenFrameForDisplay: CGRect { screenFrame }

    override var canBecomeKey: Bool { true }

    func drawHoverHighlight(_ globalRect: CGRect?) {
        dimSelectionView.hoverFrame = globalRect
    }

    func drawSelection(_ globalRect: CGRect) {
        selection = globalRect
        dimSelectionView.selection = globalRect
        // 尺寸提示：左上角坐标（显示器内、左上原点）+ 尺寸
        let x = Int(globalRect.minX - screenFrame.origin.x)
        let yFromTop = Int(screenFrame.maxY - globalRect.maxY)
        sizeLabel.stringValue = "\(x), \(yFromTop) · \(Int(globalRect.width)) × \(Int(globalRect.height))"
        sizeLabel.frame.origin = CGPoint(
            x: globalRect.origin.x - screenFrame.origin.x + 8,
            y: screenFrame.height - (globalRect.origin.y - screenFrame.origin.y) - 28
        )
        sizeLabel.isHidden = false
    }

    /// 鼠标移动/拖拽时刷新十字线和放大镜
    private func updateOverlay(at globalPoint: CGPoint) {
        let local = CGPoint(
            x: globalPoint.x - screenFrame.origin.x,
            y: globalPoint.y - screenFrame.origin.y
        )
        crosshairView.update(at: local)
        magnifierView.update(cursorPoint: globalPoint)
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.cancel()
    }

    override func mouseDown(with event: NSEvent) {
        controller?.mouseDown(at: NSEvent.mouseLocation, panel: self)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        controller?.mouseDragged(to: location)
        updateOverlay(at: location)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        controller?.mouseMovedOrHovered(at: location)
        updateOverlay(at: location)
    }

    override func mouseUp(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        // 按下后未拖动（<4pt）→ 视为窗口吸附单击
        if let origin = controller?.currentOrigin, hypot(origin.x - location.x, origin.y - location.y) < 4 {
            controller?.clickAt(globalPoint: location)
        } else {
            controller?.mouseUp(at: location)
        }
    }
}

extension RegionSelectorPanel {
    fileprivate var currentOrigin: CGPoint? {
        controller?.currentOriginInternal
    }
}

extension RegionSelectorController {
    var currentOrigin: CGPoint? { currentOriginInternal }
}

/// 全屏十字线（Snipaste 式）：两条 1px 白线跟随鼠标
private final class CrosshairView: NSView {
    private let vLine = CALayer()
    private let hLine = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for layer in [vLine, hLine] {
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            self.layer?.addSublayer(layer)
        }
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(at localPoint: CGPoint) {
        isHidden = false
        vLine.frame = CGRect(x: localPoint.x - 0.5, y: 0, width: 1, height: bounds.height)
        hLine.frame = CGRect(x: 0, y: localPoint.y - 0.5, width: bounds.width, height: 1)
    }
}

/// 跟随鼠标的放大镜（Snipaste 式）：像素网格 + RGB + 坐标。
/// 数据源是同一张冻结图，零额外抓图；坐标换算与 cropRegion 同一套数学（y 不翻转）。
private final class MagnifierView: NSView {
    static let columns = 12
    static let rows = 8
    static let pixelSize: CGFloat = 16
    static let infoHeight: CGFloat = 44

    private let frozenImage: CGImage?
    private let displayFrame: CGRect
    private let scale: CGFloat
    private var cursorPoint: CGPoint = .zero
    private let rgbLabel = NSTextField(labelWithString: "")
    private let coordLabel = NSTextField(labelWithString: "")

    init(frozenImage: CGImage?, displayFrame: CGRect) {
        self.frozenImage = frozenImage
        self.displayFrame = displayFrame
        self.scale = frozenImage.map { CGFloat($0.width) / displayFrame.width } ?? 1
        let width = CGFloat(Self.columns) * Self.pixelSize + 4
        let height = CGFloat(Self.rows) * Self.pixelSize + Self.infoHeight + 4
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.15).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        isHidden = true

        rgbLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        rgbLabel.textColor = .labelColor
        rgbLabel.backgroundColor = .clear
        rgbLabel.isBordered = false
        rgbLabel.isEditable = false
        rgbLabel.frame = NSRect(x: 10, y: 22, width: width - 20, height: 16)
        coordLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        coordLabel.textColor = .secondaryLabelColor
        coordLabel.backgroundColor = .clear
        coordLabel.isBordered = false
        coordLabel.isEditable = false
        coordLabel.frame = NSRect(x: 10, y: 6, width: width - 20, height: 16)
        addSubview(rgbLabel)
        addSubview(coordLabel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// 光标移动时调用：刷新网格、RGB、坐标，并把放大镜摆到光标附近（不出屏）
    func update(cursorPoint globalPoint: CGPoint) {
        cursorPoint = globalPoint
        isHidden = false
        needsDisplay = true
        updateLabels()
        layoutNearCursor()
    }

    private func layoutNearCursor() {
        guard let superview else { return }
        // 光标在面板内容坐标里（原点左下）
        let local = CGPoint(
            x: cursorPoint.x - displayFrame.origin.x,
            y: cursorPoint.y - displayFrame.origin.y
        )
        var origin = CGPoint(x: local.x + 24, y: local.y - 24 - bounds.height)
        if origin.x + bounds.width > superview.bounds.width {
            origin.x = local.x - 24 - bounds.width
        }
        if origin.y < 0 {
            origin.y = local.y + 24
        }
        origin.x = max(0, min(origin.x, superview.bounds.width - bounds.width))
        origin.y = max(0, min(origin.y, superview.bounds.height - bounds.height))
        frame.origin = origin
    }

    private func updateLabels() {
        // 显示坐标：显示器内、左上原点
        let localX = cursorPoint.x - displayFrame.origin.x
        let localYFromTop = displayFrame.height - (cursorPoint.y - displayFrame.origin.y)
        coordLabel.stringValue = "x \(Int(localX)) · y \(Int(localYFromTop))"
        if let color = pixelColor(at: cursorPoint) {
            rgbLabel.stringValue = "#\(color.hex) · R \(color.r) G \(color.g) B \(color.b)"
        } else {
            rgbLabel.stringValue = ""
        }
    }

    /// 读光标处 1 个像素的颜色（1×1 位图上下文取样，开销可忽略）
    private func pixelColor(at globalPoint: CGPoint) -> (r: Int, g: Int, b: Int, hex: String)? {
        guard let frozenImage else { return nil }
        let px = (globalPoint.x - displayFrame.origin.x) * scale
        let py = (globalPoint.y - displayFrame.origin.y) * scale
        let src = CGRect(x: px, y: py, width: 1, height: 1).integral
        guard src.minX >= 0, src.minY >= 0,
              src.maxX <= CGFloat(frozenImage.width),
              src.maxY <= CGFloat(frozenImage.height),
              let one = frozenImage.cropping(to: src) else { return nil }
        guard let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = ctx.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: 4)
        let r = Int(bytes[0]), g = Int(bytes[1]), b = Int(bytes[2])
        return (r, g, b, String(format: "%02X%02X%02X", r, g, b))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let frozenImage, let ctx = NSGraphicsContext.current?.cgContext else { return }
        // 光标像素（与 cropRegion 同一套数学：y 不翻转）
        let px = (cursorPoint.x - displayFrame.origin.x) * scale
        let py = (cursorPoint.y - displayFrame.origin.y) * scale
        let cols = Self.columns, rows = Self.rows
        let cx = min(max(px, CGFloat(cols) / 2), CGFloat(frozenImage.width) - CGFloat(cols) / 2)
        let cy = min(max(py, CGFloat(rows) / 2), CGFloat(frozenImage.height) - CGFloat(rows) / 2)
        let src = CGRect(
            x: cx - CGFloat(cols) / 2, y: cy - CGFloat(rows) / 2,
            width: CGFloat(cols), height: CGFloat(rows)
        ).integral
        guard let crop = frozenImage.cropping(to: src) else { return }
        let gridRect = CGRect(
            x: 2, y: Self.infoHeight + 2,
            width: bounds.width - 4, height: CGFloat(rows) * Self.pixelSize
        )
        ctx.interpolationQuality = .none
        ctx.draw(crop, in: gridRect)
        // 网格线
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor)
        ctx.setLineWidth(1)
        for i in 1..<cols {
            let x = gridRect.minX + CGFloat(i) * Self.pixelSize
            ctx.move(to: CGPoint(x: x, y: gridRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: gridRect.maxY))
        }
        for j in 1..<rows {
            let y = gridRect.minY + CGFloat(j) * Self.pixelSize
            ctx.move(to: CGPoint(x: gridRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: gridRect.maxX, y: y))
        }
        ctx.strokePath()
        // 中心像素红框（第 6 列、第 4 行，左下原点）
        let centerCell = CGRect(
            x: gridRect.minX + CGFloat(cols / 2) * Self.pixelSize,
            y: gridRect.minY + CGFloat(rows / 2) * Self.pixelSize,
            width: Self.pixelSize, height: Self.pixelSize
        )
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(centerCell.insetBy(dx: 1, dy: 1))
    }
}

/// 暗幕视图：选区外半透明黑，选区边框白色 1px，悬停窗口高亮
///
/// 图层化绘制（旧版是 draw(_:) 全屏 CPU 重绘，拖拽掉帧）：暗幕用 even-odd
/// CAShapeLayer 挖空，边框各用一个 CAShapeLayer；拖拽时只改 layer，不重画整屏。
private final class SelectionView: NSView {
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let hoverBorderLayer = CAShapeLayer()

    var selection: CGRect = .zero {
        didSet { layoutLayers() }
    }
    var hoverFrame: CGRect? = nil {
        didSet { layoutLayers() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.28).cgColor
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        borderLayer.lineWidth = 1
        hoverBorderLayer.fillColor = NSColor.clear.cgColor
        hoverBorderLayer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
        hoverBorderLayer.lineWidth = 2
        layer?.addSublayer(dimLayer)
        layer?.addSublayer(borderLayer)
        layer?.addSublayer(hoverBorderLayer)
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        guard let layer else { return }
        // 亮区 = 选区（拖拽中）或悬停窗口（未拖拽）；其余全部压暗
        let brightGlobal: CGRect?
        if selection.width > 0 {
            brightGlobal = selection
        } else {
            brightGlobal = hoverFrame
        }
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        if let brightGlobal {
            let brightLocal = convert(brightGlobal, from: nil).intersection(bounds)
            if !brightLocal.isEmpty {
                dimPath.addRect(brightLocal)
            }
        }
        dimLayer.path = dimPath
        dimLayer.frame = bounds

        if selection.width > 0 {
            let local = convert(selection, from: nil)
            borderLayer.path = CGPath(rect: local.insetBy(dx: 0.5, dy: 0.5), transform: nil)
            borderLayer.frame = bounds
            borderLayer.isHidden = false
        } else {
            borderLayer.isHidden = true
        }

        if let hover = hoverFrame, selection.width == 0 {
            let localHover = convert(hover, from: nil).intersection(bounds)
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
    }
}
