import AppKit
import SwiftUI

/// 搜索浮窗（borderless，Esc / ✕ / 点击外部关闭）
final class SearchPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

extension Notification.Name {
    static let searchPanelShouldReload = Notification.Name("com.lenso.searchPanelShouldReload")
}

/// 浮层式全局搜索（模糊背景 + 瀑布流画廊）
@MainActor
final class SearchPanelController {
    static let shared = SearchPanelController()
    private var panel: SearchPanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    func show() {
        if let panel {
            NotificationCenter.default.post(name: .searchPanelShouldReload, object: nil)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SearchPanelView { [weak self] in
            self?.hide()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua) // 与主界面一致的浅色

        // 半屏浮层：固定尺寸，优先使用上次的位置
        let screen = Self.screenUnderMouse()
        let size = NSSize(width: 960, height: 700)
        let frame = Self.restoredFrame(size: size, on: screen)

        let panel = SearchPanel(
            contentRect: frame,
            // 可激活面板：搜索框需要输入法上下文，否则中文打不进来
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.onCancel = { [weak self] in self?.hide() }
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        // Esc 兜底：通知 SearchPanelView 优先关闭详情弹层，无弹层时关闭浮层
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                NotificationCenter.default.post(name: .searchPanelEscapePressed, object: nil)
                return nil
            }
            return event
        }

        // 切到其它应用时自动收起
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    // MARK: - 位置记忆

    private static let originKey = "searchPanel.frameOrigin"

    /// 上次打开的位置；若已不在任何屏幕的可见区域内（换屏/改分辨率），回落到默认位置
    private static func restoredFrame(size: NSSize, on screen: NSScreen) -> NSRect {
        if let raw = UserDefaults.standard.string(forKey: originKey) {
            let parts = raw.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                let rect = NSRect(x: parts[0], y: parts[1], width: size.width, height: size.height)
                let visibleSomewhere = NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
                if visibleSomewhere { return rect }
            }
        }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height - 80
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func saveOrigin(_ frame: NSRect) {
        UserDefaults.standard.set("\(frame.origin.x),\(frame.origin.y)", forKey: originKey)
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let panel { Self.saveOrigin(panel.frame) }
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}
