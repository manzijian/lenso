import SwiftUI
import AppKit

@main
struct LENSOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var shortcutStore = ShortcutStore.shared
    @State private var settings = AppSettings.shared

    init() {
        // MCP (Model Context Protocol) 模式：命令行带 mcp 参数时，以非 GUI 纯协议模式运行
        if CommandLine.arguments.contains("mcp") || CommandLine.arguments.contains("--mcp") {
            LensoMCPServer.run()
            exit(0)
        }
    }

    var body: some Scene {
        // 主图库窗口 — 单例窗口（重复点击"打开图库"只聚焦，不再叠开新窗）
        Window("图库", id: "library") {
            LibraryWindowView()
                .background(WindowConfigurator(autosaveName: "lenso.library.window"))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .ignoresSafeArea()
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 720)

        // 设置窗口（单例）
        Window("设置", id: "settings") {
            SettingsWindowView()
                .background(WindowConfigurator(autosaveName: "lenso.settings.window"))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .ignoresSafeArea()
                .frame(minWidth: 620, minHeight: 420)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 680, height: 460)

        // 顶部菜单栏：所有快捷操作收拢成一个菜单，避免菜单过多
        .commands {
            CommandMenu("快捷操作") {
                Button("区域截图") {
                    CaptureCoordinator.shared.startRegionCapture()
                }
                .keyboardShortcut(shortcut(for: .captureRegion))

                Button("预览最新截图") {
                    if let newest = try? ScreenshotStore.shared.list().first,
                       let cgImage = ScreenshotStore.shared.loadImage(newest) {
                        CaptureCoordinator.shared.pin(image: cgImage, isPreview: true)
                    }
                }
                .keyboardShortcut(shortcut(for: .previewLatest))

                Divider()

                Button("打开图库") {
                    openWindow(id: "library")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(shortcut(for: .openLibrary))

                Button("全局搜索") {
                    SearchPanelController.shared.show()
                }
                .keyboardShortcut(shortcut(for: .globalSearch))

                Button("剪贴板历史") {
                    ClipboardPanelController.shared.show()
                }
                .keyboardShortcut(shortcut(for: .clipboardHistory))

                Divider()

                Button("数据看板") {
                    openWindow(id: "library")
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: .openAnalyticsSection, object: nil)
                }
                .keyboardShortcut(shortcut(for: .openAnalytics))

                Button("打开设置") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(shortcut(for: .openSettings))

                Divider()

                Button("检查更新…") {
                    Task { await UpdateChecker.shared.checkInteractively() }
                }
            }
        }
    }

    /// 菜单快捷键统一从 `ShortcutStore` 读取，设置页修改后即时生效。
    private func shortcut(for action: ShortcutAction) -> KeyboardShortcut {
        let combo = shortcutStore.combo(for: action)
        return KeyboardShortcut(combo.keyEquivalent, modifiers: combo.eventModifiers)
    }
}

/// 把 `LensoMark` 的光圈几何预渲染成 NSImage，供 NSStatusItem 菜单栏图标使用。
/// 菜单栏上下文不会渲染 SwiftUI `Canvas`，但可以正常显示模板 NSImage。
@MainActor
enum LensoStatusIcon {
    static func image(for style: MenuBarIconStyle) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14.0, weight: .regular)
        if let img = NSImage(systemSymbolName: style.systemSymbolName, accessibilityDescription: "LENSO")?.withSymbolConfiguration(config) {
            img.isTemplate = true
            return img
        }
        let fallback = NSImage(systemSymbolName: "pin", accessibilityDescription: "LENSO") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}

// MARK: - 启动自动打开图库

/// 挂在菜单栏图标上的隐形辅助 View：
/// 菜单栏图标始终渲染（不像弹窗内容只在点击时才创建），
/// 所以这里是唯一一个 App 生命周期里必定执行的 SwiftUI 回调。
private struct WindowAutoOpener: View {
    @Environment(\.openWindow) private var openWindow
    @State private var hasOpened = false

    var body: some View {
        Color.clear
            .onAppear {
                guard !hasOpened else { return }
                hasOpened = true

                // 如果 AppDelegate 已设置 flag（默认会设置），打开图库
                if UserDefaults.standard.bool(forKey: "pendingOpenLibrary") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        openWindow(id: "library")
                        NSApp.activate(ignoringOtherApps: true)
                        UserDefaults.standard.set(false, forKey: "pendingOpenLibrary")
                    }
                }
            }
            // 兜底：如果 onAppear 还没被触发，监听通知
            .onReceive(NotificationCenter.default.publisher(for: .openLibraryOnLaunch)) { _ in
                openWindow(id: "library")
                NSApp.activate(ignoringOtherApps: true)
                UserDefaults.standard.set(false, forKey: "pendingOpenLibrary")
            }
    }
}
