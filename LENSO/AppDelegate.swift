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
        // 程序坞（下方应用栏）显示状态按设置走，默认显示，支持仅菜单栏常驻
        AppSettings.shared.applyDockVisibility()
        // 显式注册 bundle 图标，避免 Stage Manager 窗口缩略图回退到通用空白图标
        registerApplicationIcon()
        // 开始监听剪贴板（记录复制过的截图与文字，含来源应用）
        ClipboardMonitor.shared.start()
        // 启动本地 HTTP / SSE / MCP 服务 (端口 52888)
        LensoLocalService.shared.start()
        // 执行自动保存时长检查与过期清理
        AppSettings.shared.runAutoCleanup()
        Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in
            Task { @MainActor in
                AppSettings.shared.runAutoCleanup()
            }
        }
        // 菜单栏常驻应用不该被系统的「突然终止」回收：
        // 没有窗口时 macOS 会认为它可以随时退出，导致热键忽然全部失灵。
        ProcessInfo.processInfo.disableSuddenTermination()

        // 快捷键走直连：立刻开选区/浮窗，不等 App 激活、不依赖菜单响应链
        GlobalHotKeyManager.shared.directHandlers[.captureRegion] = {
            CaptureCoordinator.shared.startRegionCapture()
        }
        GlobalHotKeyManager.shared.directHandlers[.globalSearch] = {
            SearchPanelController.shared.show()
        }
        GlobalHotKeyManager.shared.directHandlers[.clipboardHistory] = {
            ClipboardPanelController.shared.show()
        }
        GlobalHotKeyManager.shared.directHandlers[.openAnalytics] = {
            NotificationCenter.default.post(name: .openAnalyticsSection, object: nil)
        }
        // 注册系统级全局热键：切到别的 App 也能按 ⇧⌘1 截图
        GlobalHotKeyManager.shared.refresh(using: ShortcutStore.shared)
        // 设置里改了快捷键就重新注册
        NotificationCenter.default.addObserver(
            forName: .lensoShortcutsChanged,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                GlobalHotKeyManager.shared.refresh(using: ShortcutStore.shared)
            }
        }
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
