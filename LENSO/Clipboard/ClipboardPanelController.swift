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
    private var resignObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?

    func show() {
        // 再次点击菜单即关闭（开关式）
        if panel != nil {
            hide()
            return
        }

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        } else {
            previousApp = nil
        }

        let view = ClipboardPanelView { [weak self] in self?.hide() }
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        let size = NSSize(width: 760, height: 460)
        let screen = Self.screenUnderMouse()
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
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        LensoWindowMotion.present(panel, slideY: 8, makeKey: true)

        // 延迟一帧监听 resignKey，避免创建瞬间触发误关；点击外部或切窗时自动收起
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            self.resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    func hide() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let panel = self.panel else { return }
        self.panel = nil
        let prev = previousApp
        previousApp = nil
        LensoWindowMotion.dismiss(panel, slideY: 6) { [weak self] in
            panel.close()
            // 若用户已重新打开剪贴板或打开了其他 LENSO 窗口（如 JSON 工具），不再切回旧应用
            let hasOtherVisibleWindow = NSApp.windows.contains { $0.isVisible && $0 !== panel }
            if self?.panel == nil && !hasOtherVisibleWindow && NSApp.isActive {
                prev?.activate()
            }
        }
    }
}
