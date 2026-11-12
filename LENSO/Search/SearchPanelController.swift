import AppKit
import SwiftUI

/// 搜索浮窗（borderless，Esc / ✕ / 点击外部关闭）
final class SearchPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

extension Notification.Name {
    static let searchPanelShouldReload = Notification.Name("com.lenso.searchPanelShouldReload")
}

/// 全局搜索浮动窗（参考图 4 顶部 Spotlight 风格胶囊）
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
        hosting.appearance = NSAppearance(named: .aqua)
        let size = NSSize(width: 880, height: 620)
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - 70,
            width: size.width,
            height: size.height
        )
        let panel = SearchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.onCancel = { [weak self] in self?.hide() }
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel

        // Esc 兜底
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.hide()
                return nil
            }
            return event
        }
        // 点击外部（窗口失去 key）关闭
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}
