import AppKit
import CoreGraphics
import OSLog
import ScreenCaptureKit

private let selLog = Logger(subsystem: "com.lenso.app", category: "capture")

/// 跨屏选区覆盖窗口控制器（规范 2.2：窗口精确控制走 AppKit）
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

    /// 开始选区。完成后回调选区（全局逻辑坐标）与所在显示器。
    func begin(onComplete: @escaping (CGRect, CGDirectDisplayID) -> Void) {
        // 关闭可能残留的旧面板（泄漏防护）
        end()
        self.onComplete = onComplete
        self.origin = nil
        panels = NSScreen.screens.map { RegionSelectorPanel(screen: $0, controller: self) }
        // orderFrontRegardless 绕过 App 激活状态限制，保证 screenSaver 层级面板上屏
        for panel in panels {
            panel.setFrame(panel.screenFrameForDisplay, display: true)
            panel.orderFrontRegardless()
            panel.freezeScreen()
        }
        panels.first?.makeKey()
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
        let rect = rectBetween(origin ?? .zero, globalPoint)
        hoverWindowFrame = nil
        panels.forEach {
            $0.drawHoverHighlight(nil)
            $0.drawSelection(rect)
        }
    }

    func mouseUp(at globalPoint: CGPoint) {
        guard let origin else { return }
        let rect = rectBetween(origin, globalPoint)
        self.origin = nil
        selLog.info("selector mouseUp rect=\(NSStringFromRect(rect), privacy: .public)")
        // 先取局部引用再 end()（end 会把 onComplete 置 nil、downPanel 置 nil）
        let callback = onComplete
        let downPanelRef = downPanel
        end()
        guard rect.width >= 8, rect.height >= 8 else { return } // 过滤误触
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
            callback?(rect, displayID)
        } else {
            selLog.error("no display matched for \(NSStringFromPoint(globalPoint), privacy: .public)")
        }
    }

    /// 窗口吸附：单击（按下和松开几乎同点）时选定悬停窗口
    func clickAt(globalPoint: CGPoint) {
        if let hit = hitTestWindow(at: globalPoint) {
            selLog.info("window snap click at \(NSStringFromPoint(globalPoint), privacy: .public)")
            let callback = onComplete
            let downPanelRef = downPanel
            end()
            let displayID = downPanelRef?.ownDisplayID
                ?? NSScreen.screens.first(where: { NSMouseInRect(globalPoint, $0.frame, false) })
                    .map { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID }
            if let displayID {
                callback?(hit, displayID)
            }
        }
    }

    func cancel() {
        selLog.info("selector cancelled")
        end()
    }

    private func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(a.x - b.x), height: abs(a.y - b.y)
        ).integral
    }

    private func end() {
        panels.forEach { $0.orderOut(nil) }
        panels.forEach { $0.close() }
        panels.removeAll()
        downPanel = nil
        hoverWindowFrame = nil
        onComplete = nil
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
        label.tag = Int(displayID)
        self.sizeLabel = label
        self.frozenImageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        frozenImageView.autoresizingMask = [.width, .height]
        // 暗幕+选区绘制层（叠在冻结图上方）
        self.dimSelectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
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

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(frozenImageView)
        // 暗幕+选区层必须叠在冻结图之上，否则挖空/边框全被遮住
        container.addSubview(dimSelectionView)
        container.addSubview(sizeLabel)
        self.contentView = container
        // 显式设置 frame：borderless NSPanel 的 contentRect 初始化有时不生效
        self.setFrame(screen.frame, display: false)
        selLog.info("panel init screen=\(NSStringFromRect(screen.frame), privacy: .public) frame=\(NSStringFromRect(self.frame), privacy: .public)")
    }

    var screenFrameForDisplay: CGRect { screenFrame }

    override var canBecomeKey: Bool { true }

    /// 上屏后立刻冻结当前画面（panel 显示后调用）
    func freezeScreen() {
        Task { [weak self] in
            guard let self else { return }
            let config = SCStreamConfiguration()
            config.width = Int(self.screenFrame.width)
            config.height = Int(self.screenFrame.height)
            config.showsCursor = true
            config.captureResolution = .best
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first(where: { $0.displayID == self.ownDisplayID }) else { return }
                // WWDC22 建议：按应用排除自身（本 app 所有窗口），防止 overlay/主窗口入镜
                let ownApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter: SCContentFilter
                if let ownApp {
                    filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
                } else {
                    let ownWindows = content.windows.filter { $0.windowID == UInt32(self.windowNumber) }
                    filter = SCContentFilter(display: display, excludingWindows: ownWindows)
                }
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config
                )
                await MainActor.run {
                    self.frozenImageView.image = NSImage(cgImage: image, size: self.screenFrame.size)
                    self.frozenImageView.frame = NSRect(origin: .zero, size: self.frame.size)
                }
                selLog.info("freeze ok for display \(self.ownDisplayID)")
            } catch {
                selLog.error("freeze failed: \(error.localizedDescription, privacy: .public)")
                // 冻结失败则退化为纯暗幕，不阻断选区
            }
        }
    }

    func drawHoverHighlight(_ globalRect: CGRect?) {
        dimSelectionView.hoverFrame = globalRect
    }

    func drawSelection(_ globalRect: CGRect) {
        selection = globalRect
        dimSelectionView.selection = globalRect
        // 尺寸提示
        sizeLabel.stringValue = "\(Int(globalRect.width)) × \(Int(globalRect.height))"
        sizeLabel.frame.origin = CGPoint(
            x: globalRect.origin.x - screenFrame.origin.x + 8,
            y: screenFrame.height - (globalRect.origin.y - screenFrame.origin.y) - 28
        )
        sizeLabel.isHidden = false
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.cancel()
    }

    override func mouseDown(with event: NSEvent) {
        controller?.mouseDown(at: NSEvent.mouseLocation, panel: self)
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.mouseDragged(to: NSEvent.mouseLocation)
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.mouseMovedOrHovered(at: NSEvent.mouseLocation)
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

/// 暗幕视图：选区外半透明黑，选区边框白色 1px，悬停窗口高亮
private final class SelectionView: NSView {
    var selection: CGRect = .zero {
        didSet { needsDisplay = true }
    }
    var hoverFrame: CGRect? = nil {
        didSet { needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = NSColor.black.withAlphaComponent(0.28)
        dark.setFill()
        bounds.fill()

        // 悬停吸附高亮：半透明蓝框 + 亮边（未开始拖拽时）
        if let hover = hoverFrame, selection.width == 0 {
            let localHover = convert(hover, from: nil).intersection(bounds)
            if !localHover.isEmpty {
                NSGraphicsContext.current?.compositingOperation = .clear
                localHover.fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
                let border = NSBezierPath(rect: localHover.insetBy(dx: 1, dy: 1))
                border.lineWidth = 2
                border.stroke()
            }
        }

        let local = convert(selection, from: nil)
        if !local.isNull && local.width > 0 {
            NSGraphicsContext.current?.compositingOperation = .clear
            local.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            // 边框
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: local.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }
}
