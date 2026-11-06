import SwiftUI

@main
struct LENSOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // 菜单栏入口（MVP：区域截图 + 打开窗口）
        MenuBarExtra("LENSO", systemImage: "camera.viewfinder") {
            Button("区域截图") {
                CaptureCoordinator.shared.startRegionCapture()
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            Divider()
            Button("打开图库") {
                openWindow(id: "library")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("设置…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("退出 LENSO") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        WindowGroup("图库", id: "library") {
            LibraryWindowView()
                .frame(minWidth: 920, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)

        WindowGroup("预览", id: "preview", for: UUID.self) { $screenshotID in
            PreviewWindowView(screenshotID: screenshotID)
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 640)
        .restorationBehavior(.disabled)

        WindowGroup("设置", id: "settings") {
            SettingsWindowView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 560)
        .restorationBehavior(.disabled)
    }
}
