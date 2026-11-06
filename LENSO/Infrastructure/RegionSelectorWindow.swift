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
    }

    func mouseDown(at globalPoint: CGPoint, panel: RegionSelectorPanel) {
        origin = globalPoint
        downPanel = panel
        selLog.info("selector mouseDown at \(NSStringFromPoint(globalPoint), privacy: .public)")
    }

    func mouseDragged(to globalPoint: CGPoint) {
        guard origin != nil else { return }
        let rect = rectBetween(origin ?? .zero, globalPoint)
        panels.forEach { $0.drawSelection(rect) }
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

        let container = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), panel: self)
        container.autoresizingMask = [.width, .height]
        container.addSubview(frozenImageView)
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
                // 排除自身 panel，避免拍到自己的暗幕（按 windowNumber 过滤）
                let ownWindows = content.windows.filter { $0.windowID == UInt32(self.windowNumber) }
                let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config
                )
                await MainActor.run {
                    self.frozenImageView.image = NSImage(cgImage: image, size: self.screenFrame.size)
                    self.frozenImageView.frame = NSRect(origin: .zero, size: self.frame.size)
                }
            } catch {
                selLog.error("freeze failed: \(error.localizedDescription, privacy: .public)")
                // 冻结失败则退化为纯暗幕，不阻断选区
            }
        }
    }

    func drawSelection(_ globalRect: CGRect) {
        selection = globalRect
        (contentView as? SelectionView)?.selection = globalRect
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

    override func mouseUp(with event: NSEvent) {
        controller?.mouseUp(at: NSEvent.mouseLocation)
    }
}

/// 暗幕视图：选区外半透明黑，选区边框白色 1px
private final class SelectionView: NSView {
    private weak var panel: RegionSelectorPanel?
    var selection: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    init(frame: CGRect, panel: RegionSelectorPanel) {
        self.panel = panel
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let dark = NSColor.black.withAlphaComponent(0.28)
        dark.setFill()
        bounds.fill()

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
