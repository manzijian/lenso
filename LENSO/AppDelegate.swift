import AppKit

/// 主线程隔离：要读 AppSettings（@MainActor）等主线程状态。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // 关闭所有窗口后仍常驻菜单栏
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 外观按设置走：跟随系统时不强制，默认锁定浅色（见 AppSettings）
        AppSettings.shared.applyAppearance()
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
