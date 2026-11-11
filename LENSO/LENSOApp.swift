import SwiftUI
import AppKit

@main
struct LENSOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var shortcutStore = ShortcutStore.shared
    @State private var settings = AppSettings.shared

    var body: some Scene {
        // 菜单栏图标 → 玻璃快捷面板（参考图 4 右上），使用品牌光圈图标。
        // 设置里关掉后入口消失，用 Dock 图标点开图库再进设置。
        //
        // 用 MenuBarExtra 的 isInserted 绑定而不是 if：SceneBuilder 只允许
        // #available 分支，写 if 会让 Swift 编译器在类型检查时崩掉
        // （"failed to produce diagnostic for expression"）。绑定读写同一个
        // @Observable 设置项，设置一改，菜单栏入口立刻出现/消失。
        MenuBarExtra(isInserted: Binding(
            get: { AppSettings.shared.showMenuBarIcon },
            set: { AppSettings.shared.showMenuBarIcon = $0 }
        )) {
            MenuBarPanelView()
        } label: {
            Image(nsImage: LensoStatusIcon.image(for: AppSettings.shared.menuBarIconStyle))
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        // 主图库窗口 — 单例窗口（重复点击“打开图库”只聚焦，不再叠开新窗）
        Window("图库", id: "library") {
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

        // 设置窗口（单例）
        Window("设置", id: "settings") {
            SettingsWindowView()
                .background(WindowConfigurator())
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .ignoresSafeArea()
                .frame(minWidth: 620, minHeight: 420)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 680, height: 460)

        // 顶部菜单栏：截图 / 图库 / 搜索 / 设置
        .commands {
            CommandMenu("截图") {
                Button("区域截图") {
                    CaptureCoordinator.shared.startRegionCapture()
                }
                .keyboardShortcut(shortcut(for: .captureRegion))
            }
            CommandMenu("图库") {
                Button("打开图库") {
                    openWindow(id: "library")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(shortcut(for: .openLibrary))
                Button("预览最新截图") {
                    if let newest = try? ScreenshotStore.shared.list().first {
                        openWindow(id: "preview", value: newest.id)
                    }
                }
                .keyboardShortcut(shortcut(for: .previewLatest))
            }
            CommandMenu("搜索") {
                Button("全局搜索") {
                    SearchPanelController.shared.show()
                }
                .keyboardShortcut(shortcut(for: .globalSearch))
                Button("剪贴板历史") {
                    ClipboardPanelController.shared.show()
                }
                .keyboardShortcut(shortcut(for: .clipboardHistory))
            }
            CommandMenu("设置") {
                Button("打开设置") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(shortcut(for: .openSettings))
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
        let config = NSImage.SymbolConfiguration(pointSize: 14.5, weight: .medium)
        if let img = NSImage(systemSymbolName: style.systemSymbolName, accessibilityDescription: "LENSO")?.withSymbolConfiguration(config) {
            img.isTemplate = true
            return img
        }
        let fallback = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "LENSO") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}
