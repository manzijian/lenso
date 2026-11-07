import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // 关闭所有窗口后仍常驻菜单栏
    }

    // 不再强制 .accessory：使用 .regular 策略（默认），lenso 有 Dock 图标、
    // 参与台前调度（Stage Manager）和 App 切换器。菜单栏入口由 MenuBarExtra 独立提供。
}
