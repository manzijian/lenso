import AppKit
import SwiftUI

/// 全局搜索浮动窗（参考图 4 顶部 Spotlight 风格胶囊）
@MainActor
final class SearchPanelController {
    static let shared = SearchPanelController()
    private var panel: NSPanel?

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SearchPanelView { [weak self] in
            self?.hide()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        let size = NSSize(width: 760, height: 420)
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - 120,
            width: size.width,
            height: size.height
        )
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}
