import SwiftUI

@main
struct LENSOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("图库", id: "library") {
            LibraryWindowView()
                .frame(minWidth: 920, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("预览", id: "preview", for: UUID.self) { $screenshotID in
            PreviewWindowView(screenshotID: screenshotID)
        }
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)

        Window("设置", id: "settings") {
            SettingsWindowView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            EmptyView() // 设置存储接入点
        }
    }
}
