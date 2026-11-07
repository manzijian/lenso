import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // 关闭所有窗口后仍常驻菜单栏
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 参考设计为浅色玻璃风格：固定浅色外观，避免系统深色模式下文字/材质反转
        NSApp.appearance = NSAppearance(named: .aqua)
        // 显式注册 bundle 图标，避免 Stage Manager 窗口缩略图回退到通用空白图标
        registerApplicationIcon()
        // 开始监听剪贴板（记录复制过的截图与文字，含来源应用）
        ClipboardMonitor.shared.start()
    }

    private func registerApplicationIcon() {
        let icon = Bundle.main
            .url(forResource: "AppIcon", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(named: "AppIcon")

        guard let icon else { return }
        NSApp.applicationIconImage = icon
        NSApp.dockTile.display()
    }
}
