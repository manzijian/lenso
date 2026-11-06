import SwiftUI
import AppKit

@main
struct LENSOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // 菜单栏图标 → 玻璃快捷面板（参考图 4 右上）
        MenuBarExtra("LENSO", systemImage: "viewfinder") {
            MenuBarPanelView()
        }
        .menuBarExtraStyle(.window)

        // 主图库窗口 — 透明浮窗 + 圆角内容
        WindowGroup("图库", id: "library") {
            LibraryWindowView()
                .background(WindowConfigurator())
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .ignoresSafeArea()
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 720)

        // 预览窗口
        WindowGroup("预览", id: "preview", for: UUID.self) { $screenshotID in
            PreviewWindowView(screenshotID: screenshotID)
                .background(WindowConfigurator())
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .ignoresSafeArea()
                .frame(minWidth: 560, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 820, height: 560)
        .restorationBehavior(.disabled)

        // 设置窗口
        WindowGroup("设置", id: "settings") {
            SettingsWindowView()
                .background(WindowConfigurator())
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .ignoresSafeArea()
                .frame(minWidth: 620, minHeight: 420)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 680, height: 460)
        .restorationBehavior(.disabled)

        // 顶部菜单栏：截图 / 图库 / 搜索 / 设置
        .commands {
            CommandMenu("截图") {
                Button("区域截图") {
                    CaptureCoordinator.shared.startRegionCapture()
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            }
            CommandMenu("图库") {
                Button("打开图库") {
                    openWindow(id: "library")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("0", modifiers: [.command])
                Button("预览最新截图") {
                    if let newest = try? ScreenshotStore.shared.list().first {
                        openWindow(id: "preview", value: newest.id)
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandMenu("搜索") {
                Button("全局搜索") {
                    SearchPanelController.shared.show()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
            CommandMenu("设置") {
                Button("打开设置") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
