import AppKit
import SwiftUI

/// 剪贴板历史浮窗（Esc / ✕ / 点击外部关闭）
final class ClipboardPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
final class ClipboardPanelController {
    static let shared = ClipboardPanelController()
    private var panel: ClipboardPanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    func show() {
        // 再次点击菜单即关闭（开关式）
        if panel != nil {
            hide()
            return
        }
        let view = ClipboardPanelView { [weak self] in self?.hide() }
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        let size = NSSize(width: 760, height: 460)
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let panel = ClipboardPanel(
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
        panel.onCancel = { [weak self] in self?.hide() }
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
        // 不监听 resignKey：面板创建瞬间可能收到该通知导致“刚开就关”。
        // 关闭方式：Esc / ✕ / 再次点击菜单。
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
