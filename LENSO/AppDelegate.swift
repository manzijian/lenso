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
        // 系统自带菜单统一为中文，避免中英混排
        localizeSystemMenus()
        // SwiftUI 在启动后还会重建一次主菜单，稍后再处理一遍
        for delay in [0.4, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    (NSApp.delegate as? AppDelegate)?.localizeSystemMenus()
                }
            }
        }
        // 程序坞（下方应用栏）显示状态按设置走，默认显示，支持仅菜单栏常驻
        AppSettings.shared.applyDockVisibility()
        // 显式注册 bundle 图标，避免 Stage Manager 窗口缩略图回退到通用空白图标
        registerApplicationIcon()
        // 开始监听剪贴板（记录复制过的截图与文字，含来源应用）
        ClipboardMonitor.shared.start()
        // 写入桌面小组件快照（截图/图库变化时刷新，另每 5 分钟兜底）
        WidgetSnapshotCoordinator.shared.start()
        // 预热截图框架，第一次按热键时冻结画面更快
        Task.detached(priority: .utility) {
            await ScreenCaptureService.prewarm()
        }
        // 启动本地 HTTP / SSE / MCP 服务 (端口 52888，按设置开启或关闭)
        AppSettings.shared.applyMCPServerState()
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
        // 自建状态栏图标（替代 SwiftUI MenuBarExtra，彻底解决面板打开错位）
        StatusBarController.shared.install()

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

        // 启动后自动打开图库主窗口（菜单栏应用默认不弹出任何窗口）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            UserDefaults.standard.set(true, forKey: "pendingOpenLibrary")
            NotificationCenter.default.post(name: .openLibraryOnLaunch, object: nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        // 从 GitHub Releases 静默检查更新（每天最多一次，失败不打扰）
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            UpdateChecker.shared.checkIfDue()
        }
    }

    /// SwiftUI 生成的系统菜单（Edit / View / Window / Help）跟随工程开发语言，
    /// 这里再兜底改一次中文，保证顶部菜单不出现中英混排。
    private func localizeSystemMenus() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let titles: [String: String] = [
            "Edit": "编辑",
            "View": "显示",
            "Window": "窗口",
            "Help": "帮助",
        ]
        for item in mainMenu.items {
            if let localized = titles[item.title] {
                item.title = localized
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
