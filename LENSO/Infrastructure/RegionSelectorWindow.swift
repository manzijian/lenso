import AppKit
import CoreGraphics
import OSLog
import ScreenCaptureKit

// MARK: - 选区控制器

/// 跨屏选区覆盖窗口控制器（规范 2.2：窗口精确控制走 AppKit）。
///
/// 流程：快捷键 → 透明面板立刻上屏（不抓图）→ 悬停窗口吸附 / 拖拽框选 →
/// 松手后选区停住（可移动、可拉手柄、方向键 1px 微调、Shift 10px）→
/// 回车 / 双击 / 点「完成」确认 → coordinator 抓图、开编辑器、关选区。
@MainActor
final class RegionSelectorController: NSObject {
    private var panels: [RegionSelectorPanel] = []
    private var onComplete: ((CGRect, CGDirectDisplayID, CGWindowID, CGImage?) -> Void)?
    /// 各显示器的冻结帧（按下热键那一刻的画面）
    private var frozenFrames: [CGDirectDisplayID: CGImage] = [:]
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

    /// 开始选区。面板立刻上屏，同时后台冻结每一块屏（Snipaste 的做法）。
    /// 回调带上该屏的冻结帧，确认时直接用它开编辑器，不用再等抓图。
    func begin(onComplete: @escaping (CGRect, CGDirectDisplayID, CGWindowID, CGImage?) -> Void) {
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
        NSCursor.crosshair.set()
        // 键盘（Esc 取消 / Return 确认）依赖面板是 key window。
        // 从别的 App 按热键时，NSApp.activate 是异步的，立刻 makeKey 会失败，
        // 表现就是「浮层出来了但 Esc / 回车没反应」。所以激活后下一拍再 makeKey。
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDismissed else { return }
            self.panels.first(where: { $0.screenFrameForDisplay.contains(NSEvent.mouseLocation) })?
                .makeKey()
            if NSApp.keyWindow == nil { self.panels.first?.makeKey() }
        }
        freezeDisplays()
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

    /// 后台冻结每块屏：把各面板排除在外各抓一张。
    /// 抓到就铺到对应面板底层——用户看到画面「定住」，和 Snipaste 一致。
    private func freezeDisplays() {
        frozenFrames.removeAll()
        let panelIDs = panels.map { (displayID: $0.ownDisplayID, windowNumber: CGWindowID($0.windowNumber)) }
        Task { [weak self] in
            for entry in panelIDs {
                guard let self, !self.isDismissed else { return }
                guard let image = try? await ScreenCaptureService().captureDisplayExcluding(
                    displayID: entry.displayID, excludedWindowIDs: [entry.windowNumber]
                ) else { continue }
                guard !self.isDismissed else { return }
                self.frozenFrames[entry.displayID] = image
                self.panels.first(where: { $0.ownDisplayID == entry.displayID })?
                    .setFrozenImage(image)
            }
            selLog.info("frozen \(self?.frozenFrames.count ?? 0) display(s)")
        }
    }

    /// CGWindowList 取在屏窗口：排除自身，允许吸附其他 App 的窗口；
    /// 层级 >= 0 且 <= 25，太小/透明的不要。
    static func loadSnappableWindows() -> [(windowID: CGWindowID, frame: CGRect, title: String)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // CGWindowBounds 用的是「主屏左上角为原点、y 向下」的坐标系，
        // 所以换算回 AppKit 全局坐标时，基准必须是**主屏**的高度，
        // 不能用所有屏里最大的 maxY——接上更高的外接屏后，窗口吸附会整体偏移。
        let mainScreenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        var result: [(CGWindowID, CGRect, String)] = []
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 0 && layer <= 25,
                  let ownerPID = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID != ownPID,
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
        hideHandles()
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
            if hoverWindowFrame != nil {
                hoverWindowFrame = nil
                panels.forEach { $0.drawHoverHighlight(nil) }
            }
            // 自由框选：1:1 紧跟鼠标光标，不强行吸附后台散落窗口边缘，保证丝滑流畅
            let rect = rectBetween(origin, globalPoint).intersection(displayFrame)
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
                    // 松手直接进标注编辑器（Snipaste 的手感：框完就是工具栏，
                    // 不需要再点一次按钮）。编辑器里仍然可以用手柄微调选区。
                    confirmSelection()
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
        onComplete?(selection, displayID, panelWindowNumber, frozenFrames[displayID])
    }

    /// 窗口吸附：单击悬停窗口直接确认
    func clickAt(globalPoint: CGPoint) {
        guard let hit = hitTestWindow(at: globalPoint),
              let downPanel else { return }
        let clamped = hit.intersection(downPanel.screenFrameForDisplay)
        guard clamped.width >= 8, clamped.height >= 8 else { return }
        // 区域截图模式下：若命中的窗口尺寸接近全屏（如桌面壁纸、Finder 背景），不作为吸附，避免意外触发全屏截图
        let screen = downPanel.screenFrameForDisplay
        if clamped.width >= screen.width - 16 && clamped.height >= screen.height - 16 {
            selLog.info("ignore full screen snap on click in region capture mode")
            return
        }
        selLog.info("window snap click at \(NSStringFromPoint(globalPoint), privacy: .public)")
        let id = downPanel.ownDisplayID
        onComplete?(clamped, id, CGWindowID(downPanel.windowNumber), frozenFrames[id])
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
        NSCursor.crosshair.set()
    }

    private func refreshSelectionViews() {
        panels.forEach { $0.drawSelection(selection) }
    }

    private func hideHandles() {
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
        frozenFrames.removeAll()
        NSCursor.arrow.set()
    }
}
