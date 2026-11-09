import AppKit
import CoreGraphics
import OSLog
import ScreenCaptureKit

private let selLog = Logger(subsystem: "com.lenso.app", category: "capture")

/// 截图丝滑 v2：Snipaste 式实时覆盖层 + 确认后抓图。
///
/// 旧版（v1）是先冻结、后上屏：快捷键按下后要等每显示器一张全屏 captureImage
/// 抓完，面板才出现，用户感觉到的就是那 0.5~1 秒的死等。
/// 新版照 Snipaste / Ta 的做法：快捷键一按，透明面板立刻上屏，选区里直接
/// 透出实时桌面；放大镜按需小范围取活像素；窗口吸附、方向键微调、拖拽
/// 调整都在选区里做完；确认那一刻才抓一张全屏（把选区面板排除在外）
/// 当编辑器背景，抓完开编辑器、再关选区，中间不露桌面。
///
/// 关键取舍（对照 Ta 的 SelectionOverlayController + ScreenCaptureService）：
/// - 不预抓冻结图；选区面板是透明 NSPanel，不画假桌面。
/// - 确认后抓全屏（不是只抓选区），因为编辑器要整屏冻结图当背景。
/// - 窗口吸附只认当时前台 App 的窗口（Ta 的策略），避免点到别的 App 的旧窗口。

// MARK: - 拖拽状态机与手柄数学（手柄数学照搬 Ta 的 SelectionRectEditor，Ta 是 MIT 协议）

/// 选区拖拽模式
private enum SelectorDragMode {
    case creating
    case moving(original: CGRect)
    case resizing(handle: SelectorResizeHandle, original: CGRect)
}

/// 选区 8 手柄
private enum SelectorResizeHandle: CaseIterable {
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

private enum SelectorRectEditor {
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

// MARK: - 选区控制器

/// 跨屏选区覆盖窗口控制器（规范 2.2：窗口精确控制走 AppKit）。
///
/// 流程：快捷键 → 透明面板立刻上屏（不抓图）→ 悬停窗口吸附 / 拖拽框选 →
/// 松手后选区停住（可移动、可拉手柄、方向键 1px 微调、Shift 10px）→
/// 回车 / 双击 / 点「完成」确认 → coordinator 抓图、开编辑器、关选区。
@MainActor
final class RegionSelectorController: NSObject {
    private var panels: [RegionSelectorPanel] = []
    private var onComplete: ((CGRect, CGDirectDisplayID, CGWindowID) -> Void)?
    private var origin: CGPoint?
    private weak var downPanel: RegionSelectorPanel?
    private var dragMode: SelectorDragMode = .creating
    private var didDrag = false
    /// 当前选区（全局 AppKit 坐标）；nil = 还没框出来
    private var selection: CGRect?
    /// 拖拽/移动/缩放时把选区夹在这个显示器内（mouseDown 的那个显示器）
    private var activeDisplayFrame: CGRect?
    /// 可吸附的窗口列表（Z 轴序）
    private var snappableWindows: [(windowID: CGWindowID, frame: CGRect, title: String)] = []
    /// 当前悬停吸附的窗口
    private var hoverWindowFrame: CGRect?
    /// 右键取消的本地事件监听
    private var rightClickMonitor: Any?
    /// 是否已被关闭（供 coordinator 在回调 Task 里判断用户是否已 Esc 取消）
    private(set) var isDismissed = false

    /// 开始选区。面板立刻上屏，不抓图、不等权限以外的任何东西。
    func begin(onComplete: @escaping (CGRect, CGDirectDisplayID, CGWindowID) -> Void) {
        // 关闭可能残留的旧面板（泄漏防护）
        end()
        isDismissed = false
        self.onComplete = onComplete
        self.origin = nil
        self.selection = nil
        panels = NSScreen.screens.map { RegionSelectorPanel(screen: $0, controller: self) }
        // orderFrontRegardless 绕过 App 激活状态限制，保证 screenSaver 层级面板上屏
        for panel in panels {
            panel.setFrame(panel.screenFrameForDisplay, display: true)
            panel.orderFrontRegardless()
        }
        panels.first?.makeKey()
        NSCursor.crosshair.set()
        // 十字线立刻定位到当前光标：不等第一次 mouseMoved，浮层一出现就有反馈
        let cursor = NSEvent.mouseLocation
        panels.forEach { $0.syncCrosshair(to: cursor) }
        // 窗口枚举（CGWindowListCopyWindowInfo）放到下一拍再做：
        // 它会阻塞主线程十几毫秒，挡在浮层上屏之后、第一次鼠标事件之前，
        // 手感上就是「浮层出来了但第一下拖动有点黏」。
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDismissed else { return }
            self.snappableWindows = Self.loadSnappableWindows()
            selLog.info("selector shown live, snappable windows: \(self.snappableWindows.count)")
        }

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self, self.panels.contains(where: { event.window === $0 }) else { return event }
            self.cancel()
            return nil
        }
    }

    /// CGWindowList 取窗口：只认当时前台 App 的窗口（Ta 的策略），
    /// 避免切到别的 App 后仍命中旧窗口；层级 >= 0，太小/透明的不要。
    static func loadSnappableWindows() -> [(windowID: CGWindowID, frame: CGRect, title: String)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // CGWindowBounds 用的是「主屏左上角为原点、y 向下」的坐标系，
        // 所以换算回 AppKit 全局坐标时，基准必须是**主屏**的高度，
        // 不能用所有屏里最大的 maxY——接上更高的外接屏后，窗口吸附会整体偏移。
        let mainScreenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        var result: [(CGWindowID, CGRect, String)] = []
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 0,
                  let ownerPID = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  frontmostPID == nil || ownerPID == frontmostPID,
                  let boundsDict = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = boundsDict["Width"], let height = boundsDict["Height"],
                  width >= 24, height >= 16,
                  let alpha = w[kCGWindowAlpha as String] as? CGFloat, alpha > 0.01,
                  let windowID = w[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            let x = boundsDict["X"] ?? 0
            let yTop = boundsDict["Y"] ?? 0
            // CGWindowBounds：全局左上原点 → AppKit 全局左下原点
            let appKitY = mainScreenHeight - yTop - height
            let frame = CGRect(x: x, y: appKitY, width: width, height: height)
            let title = w[kCGWindowName as String] as? String ?? ""
            result.append((windowID, frame.integral, title))
        }
        return result
    }

    /// 命中测试：返回鼠标所在的最顶层可吸附窗口（列表即 Z 轴序，第一个就是最顶层）
    func hitTestWindow(at globalPoint: CGPoint) -> CGRect? {
        snappableWindows.first(where: { $0.frame.contains(globalPoint) })?.frame
    }

    func mouseMovedOrHovered(at globalPoint: CGPoint) {
        // 悬停吸附高亮（未按下、还没选区时）
        guard origin == nil, selection == nil else { return }
        let hit = hitTestWindow(at: globalPoint)
        if hit != hoverWindowFrame {
            hoverWindowFrame = hit
            panels.forEach { $0.drawHoverHighlight(hit) }
        }
    }

    /// 该点的光标：手柄上是缩放光标，选区内是抓手，其余十字线
    func cursor(at globalPoint: CGPoint) -> NSCursor {
        guard let selection else { return .crosshair }
        if let handle = SelectorRectEditor.resizeHandle(at: globalPoint, for: selection) {
            return handle.cursor
        }
        return selection.contains(globalPoint) ? .openHand : .crosshair
    }

    func mouseDown(at globalPoint: CGPoint, panel: RegionSelectorPanel) {
        panel.makeKey()
        downPanel = panel
        activeDisplayFrame = panel.screenFrameForDisplay
        origin = globalPoint
        didDrag = false
        hideConfirmBar()
        if let selection {
            if let handle = SelectorRectEditor.resizeHandle(at: globalPoint, for: selection) {
                dragMode = .resizing(handle: handle, original: selection)
                handle.cursor.set()
            } else if selection.contains(globalPoint) {
                dragMode = .moving(original: selection)
                NSCursor.closedHand.set()
            } else {
                // 点在选区外：旧选区立刻清掉，开始新的框选
                dragMode = .creating
                self.selection = nil
                refreshSelectionViews()
                hoverWindowFrame = hitTestWindow(at: globalPoint)
                NSCursor.crosshair.set()
            }
        } else {
            dragMode = .creating
            hoverWindowFrame = hitTestWindow(at: globalPoint)
            NSCursor.crosshair.set()
        }
        selLog.info("selector mouseDown at \(NSStringFromPoint(globalPoint), privacy: .public)")
    }

    func mouseDragged(to globalPoint: CGPoint) {
        guard let origin, let displayFrame = activeDisplayFrame else { return }
        guard didDrag || hypot(globalPoint.x - origin.x, globalPoint.y - origin.y) >= 3 else { return }
        didDrag = true
        switch dragMode {
        case .creating:
            hoverWindowFrame = nil
            panels.forEach { $0.drawHoverHighlight(nil) }
            let rect = snapRect(rectBetween(origin, globalPoint)).intersection(displayFrame)
            selection = rect.width >= 1 && rect.height >= 1 ? rect : nil
        case .moving(let original):
            NSCursor.closedHand.set()
            selection = SelectorRectEditor.moved(original, by: CGPoint(x: globalPoint.x - origin.x, y: globalPoint.y - origin.y), inside: displayFrame)
        case .resizing(let handle, let original):
            handle.cursor.set()
            selection = SelectorRectEditor.resized(original, handle: handle, to: globalPoint, inside: displayFrame)
        }
        refreshSelectionViews()
    }

    func mouseUp(at globalPoint: CGPoint) {
        guard origin != nil else { return }
        origin = nil
        switch dragMode {
        case .creating:
            if didDrag {
                // 拖出选区：太小算误触，清掉、保持打开（Ta 的做法，不直接关）
                if let selection, selection.width >= 8, selection.height >= 8 {
                    enterSelectedState()
                } else {
                    selection = nil
                    refreshSelectionViews()
                }
            } else {
                // 单击：悬停窗口直接确认，没窗口就保持打开
                clickAt(globalPoint: globalPoint)
            }
        case .moving, .resizing:
            // 移动/缩放完回到可确认状态
            if didDrag, let selection, selection.width >= 8, selection.height >= 8 {
                enterSelectedState()
            } else if let selection {
                self.selection = selection
                enterSelectedState()
            }
        }
        dragMode = .creating
        didDrag = false
    }

    /// 键盘：Esc 取消；回车确认；方向键 1px 微调（Shift 10px）
    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            cancel()
            return true
        case 36, 76: // Return / keypad Enter
            if selection != nil { confirmSelection() }
            return true
        case 123, 124, 125, 126: // 左 / 右 / 下 / 上
            guard selection != nil else { return true }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case 123: nudge(dx: -step, dy: 0)
            case 124: nudge(dx: step, dy: 0)
            case 125: nudge(dx: 0, dy: -step)
            case 126: nudge(dx: 0, dy: step)
            default: break
            }
            return true
        default:
            return false
        }
    }

    /// 方向键微调：整体平移选区，夹在当前显示器内
    func nudge(dx: CGFloat, dy: CGFloat) {
        guard let selection, let displayFrame = activeDisplayFrame else { return }
        let moved = SelectorRectEditor.moved(selection, by: CGPoint(x: dx, y: dy), inside: displayFrame)
        self.selection = moved
        refreshSelectionViews()
        downPanel?.showConfirmBar(for: moved)
    }

    /// 双击选区内确认（Snipaste 同款）
    func doubleClick(at globalPoint: CGPoint) {
        guard let selection, selection.contains(globalPoint) else { return }
        confirmSelection()
    }

    /// 确认：回调给 coordinator（抓图、开编辑器、关选区都在那边做）。
    /// 这里不 end()，编辑器先上、选区后关，中间不露桌面。
    func confirmSelection() {
        guard let selection, selection.width >= 8, selection.height >= 8,
              let downPanel else { return }
        let displayID = downPanel.ownDisplayID
        let panelWindowNumber = CGWindowID(downPanel.windowNumber)
        selLog.info("selector confirmed rect=\(NSStringFromRect(selection), privacy: .public)")
        onComplete?(selection, displayID, panelWindowNumber)
    }

    /// 窗口吸附：单击悬停窗口直接确认
    func clickAt(globalPoint: CGPoint) {
        guard let hit = hitTestWindow(at: globalPoint),
              let downPanel else { return }
        selLog.info("window snap click at \(NSStringFromPoint(globalPoint), privacy: .public)")
        onComplete?(hit, downPanel.ownDisplayID, CGWindowID(downPanel.windowNumber))
    }

    /// 供 coordinator 在编辑器上屏后调用：关选区面板（不触发回调）
    func dismiss() {
        end()
    }

    func cancel() {
        selLog.info("selector cancelled")
        end()
    }

    /// 进入可确认状态：显示手柄 + 完成/取消条
    private func enterSelectedState() {
        refreshSelectionViews()
        downPanel?.setHandlesVisible(true)
        if let selection { downPanel?.showConfirmBar(for: selection) }
        NSCursor.crosshair.set()
    }

    private func refreshSelectionViews() {
        panels.forEach { $0.drawSelection(selection) }
    }

    private func hideConfirmBar() {
        panels.forEach { $0.hideConfirmBar() }
        panels.forEach { $0.setHandlesVisible(false) }
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
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
            self.rightClickMonitor = nil
        }
        panels.forEach { $0.orderOut(nil) }
        panels.forEach { $0.close() }
        panels.removeAll()
        downPanel = nil
        hoverWindowFrame = nil
        selection = nil
        onComplete = nil
        NSCursor.arrow.set()
    }
}

// MARK: - 单显示器透明覆盖面板

/// 单显示器覆盖面板：透明，选区里直接透出实时桌面 + 暗幕，选区挖空，Esc 取消。
/// 不画冻结图（v1 的冻结图上屏是卡顿主因，已删）。
final class RegionSelectorPanel: NSPanel {
    private weak var controller: RegionSelectorController?
    private let sizeLabel: NSTextField
    private let dimSelectionView: SelectionView
    private let crosshairView: CrosshairView
    private let confirmBar: ConfirmBar
    let screenFrame: CGRect
    let ownDisplayID: CGDirectDisplayID

    init(screen: NSScreen, controller: RegionSelectorController) {
        self.controller = controller
        self.screenFrame = screen.frame
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        self.ownDisplayID = displayID
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.isHidden = true
        self.sizeLabel = label
        // 暗幕+选区绘制层（直接叠在实时桌面上）
        self.dimSelectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame)
        dimSelectionView.autoresizingMask = [.width, .height]
        self.crosshairView = CrosshairView(frame: NSRect(origin: .zero, size: screen.frame.size))
        crosshairView.autoresizingMask = [.width, .height]
        self.confirmBar = ConfirmBar()
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
        confirmBar.onConfirm = { [weak controller] in controller?.confirmSelection() }
        confirmBar.onCancel = { [weak controller] in controller?.cancel() }

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(dimSelectionView)
        container.addSubview(crosshairView)
        container.addSubview(confirmBar)
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

    func drawSelection(_ globalRect: CGRect?) {
        dimSelectionView.selection = globalRect ?? .zero
        guard let globalRect else {
            sizeLabel.isHidden = true
            return
        }
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

    func setHandlesVisible(_ visible: Bool) {
        dimSelectionView.showsHandles = visible
    }

    /// 完成/取消条：优先放选区下方，没地方放上方，横向贴在选区右沿
    func showConfirmBar(for globalRect: CGRect) {
        let barSize = ConfirmBar.preferredSize
        let local = CGRect(
            x: globalRect.origin.x - screenFrame.origin.x,
            y: globalRect.origin.y - screenFrame.origin.y,
            width: globalRect.width, height: globalRect.height
        )
        let proposedBelow = local.minY - barSize.height - 10
        // 面板自身没有 bounds（那是 NSView 的），用显示器尺寸算边界
        let panelSize = screenFrame.size
        let y = proposedBelow >= 8
            ? proposedBelow
            : min(panelSize.height - barSize.height - 8, local.maxY + 10)
        let x = min(max(8, local.maxX - barSize.width), panelSize.width - barSize.width - 8)
        confirmBar.frame = CGRect(origin: CGPoint(x: x, y: y), size: barSize)
        confirmBar.isHidden = false
    }

    func hideConfirmBar() {
        confirmBar.isHidden = true
    }

    /// 浮层刚上屏时调用：不等用户移动鼠标，十字线立刻出现在当前光标处。
    /// （以前只有第一次 mouseMoved 才画十字线，浮层出现到鼠标动之间是空白的，
    ///   手感上就是「按了热键但没反应」。）
    func syncCrosshair(to globalPoint: CGPoint) {
        guard screenFrame.contains(globalPoint) else { return }
        updateOverlay(at: globalPoint)
    }

    /// 鼠标移动/拖拽时刷新十字线
    private func updateOverlay(at globalPoint: CGPoint) {
        let local = CGPoint(
            x: globalPoint.x - screenFrame.origin.x,
            y: globalPoint.y - screenFrame.origin.y
        )
        crosshairView.update(at: local)
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
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        controller?.mouseDragged(to: location)
        updateOverlay(at: location)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        controller?.mouseMovedOrHovered(at: location)
        controller?.cursor(at: location).set()
        updateOverlay(at: location)
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 {
            controller?.doubleClick(at: NSEvent.mouseLocation)
            return
        }
        controller?.mouseUp(at: NSEvent.mouseLocation)
    }
}

// MARK: - 完成/取消条

/// 选区确认条：小胶囊，两个按钮。只在选区停住后出现。
private final class ConfirmBar: NSView {
    static let preferredSize = NSSize(width: 168, height: 36)

    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    private let effectView = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true
        effectView.frame = bounds
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.frame = bounds.insetBy(dx: 8, dy: 5)
        stack.autoresizingMask = [.width, .height]

        let confirm = NSButton(title: "完成", target: self, action: #selector(confirmClicked))
        confirm.bezelStyle = .rounded
        confirm.controlSize = .small
        confirm.keyEquivalent = "\r"
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .small
        cancel.keyEquivalent = "\u{1b}"
        stack.addArrangedSubview(confirm)
        stack.addArrangedSubview(cancel)
        addSubview(stack)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func confirmClicked() { onConfirm?() }
    @objc private func cancelClicked() { onCancel?() }
}

// MARK: - 十字线与放大镜

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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        vLine.frame = CGRect(x: localPoint.x - 0.5, y: 0, width: 1, height: bounds.height)
        hLine.frame = CGRect(x: 0, y: localPoint.y - 0.5, width: bounds.width, height: 1)
        CATransaction.commit()
    }
}

// MARK: - 暗幕与选区

/// 暗幕视图：选区外半透明黑，选区边框白色 1px，悬停窗口高亮，选区 8 手柄。
///
/// 图层化绘制（旧版是 draw(_:) 全屏 CPU 重绘，拖拽掉帧）：暗幕用 even-odd
/// CAShapeLayer 挖空，边框、手柄各用一个 CAShapeLayer；拖拽时只改 layer，不重画整屏。
private final class SelectionView: NSView {
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let hoverBorderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()

    /// 本视图所在显示器在 AppKit 全局坐标下的 frame。
    ///
    /// 必须显式持有它来做「全局 → 面板局部」换算，不能用
    /// `convert(_:from: nil)`：那个方法把入参当成**窗口坐标**，不会做
    /// 屏幕原点偏移。主屏原点是 (0,0) 所以碰巧正确；外接屏原点可能是
    /// (-2560,-187)，传进去的全局坐标全是负数，intersection 后变成空矩形，
    /// 选区框、手柄、挖空全被裁掉——表现就是「外接屏上框选了但什么都没画」。
    let screenFrame: CGRect

    init(frame: NSRect, screenFrame: CGRect) {
        self.screenFrame = screenFrame
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
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.controlAccentColor.cgColor
        handlesLayer.lineWidth = 1.5
        layer?.addSublayer(dimLayer)
        layer?.addSublayer(borderLayer)
        layer?.addSublayer(hoverBorderLayer)
        layer?.addSublayer(handlesLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// AppKit 全局坐标 → 面板局部坐标（原点在面板左下）
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
        // CAShapeLayer 的 path / frame 都是可动画属性：不在事务里关掉隐式动画的话，
        // 每次拖拽更新都会补一段 0.25s 的过渡，选区会明显「追不上」光标。
        // 这是拖拽手感发飘的主要原因。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
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
            let brightLocal = localRect(brightGlobal).intersection(bounds)
            if !brightLocal.isEmpty {
                dimPath.addRect(brightLocal)
            }
        }
        dimLayer.path = dimPath
        dimLayer.frame = bounds

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
