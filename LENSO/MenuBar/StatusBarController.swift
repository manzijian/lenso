import AppKit
import SwiftUI

/// 自定义状态栏图标 + 自绘 NSPanel，替代 SwiftUI MenuBarExtra。
/// 核心原因：SwiftUI MenuBarExtra 的 `.window` 样式把面板交给系统托管，
///   它的布局周期与 SwiftUI `.mask` / `.blur` 动画不同步，导致每次打开面板错位。
///   自己持有 NSPanel，就能在 show 时先把 frame 设正确再让 SwiftUI 进场。
@MainActor
final class StatusBarController {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var eventMonitor: Any?

    private init() {}

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = LensoStatusIcon.image(for: AppSettings.shared.menuBarIconStyle)
        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    func reinstallIfNeeded() {
        let shouldShow = AppSettings.shared.showMenuBarIcon
        if shouldShow {
            install()
            let newIcon = LensoStatusIcon.image(for: AppSettings.shared.menuBarIconStyle)
            statusItem?.button?.image = newIcon
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            hide()
        }
    }

    @objc private func togglePanel(_ sender: Any?) {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if let panel {
            LensoWindowMotion.present(panel, slideY: -6, makeKey: true)
            return
        }

        let size = NSSize(width: 356, height: 420)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = false

        let rootView = MenuBarPanelView()
        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        positionPanel(panel)
        self.panel = panel

        // 全局事件：点击外部或按 Esc 关闭
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if event.type == .keyDown {
                    if event.keyCode == 53 { // Esc
                        self.hide()
                    }
                    return
                }
                // 点击事件在面板之外
                if let window = event.window, window === panel { return }
                // 如果事件在 app 内另一窗口，保留不关闭（用户可能在切窗）
                if event.window != nil && NSApp.windows.contains(event.window!) { return }
                self.hide()
            }
        }

        LensoWindowMotion.present(panel, slideY: -6, makeKey: true)
    }

    func hide() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        guard let panel = self.panel else { return }
        self.panel = nil
        LensoWindowMotion.dismiss(panel, slideY: -4)
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let button = statusItem?.button,
              let window = button.window else { return }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameInScreen = window.convertToScreen(buttonFrameInWindow)

        let screenFrame = buttonFrameInScreen
        let panelWidth = panel.frame.width
        let screen = window.screen ?? NSScreen.main!

        // 优先让面板左边缘对齐按钮左边缘；如果靠右溢出屏幕，就贴屏幕右边
        var originX = screenFrame.minX
        let maxX = screen.visibleFrame.maxX - panelWidth - 8
        if originX > maxX { originX = maxX }
        originX = max(screen.visibleFrame.minX + 8, originX)

        let originY = screenFrame.minY - panel.frame.height - 4

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
