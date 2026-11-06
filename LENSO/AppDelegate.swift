import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // 关闭所有窗口后仍常驻菜单栏
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 参考设计为浅色玻璃风格：固定浅色外观，避免系统深色模式下文字/材质反转
        NSApp.appearance = NSAppearance(named: .aqua)
        // 开始监听剪贴板（记录复制过的截图与文字，含来源应用）
        ClipboardMonitor.shared.start()
    }
}
