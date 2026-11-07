import SwiftUI
import AppKit

@main
struct LENSOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var shortcutStore = ShortcutStore.shared
    @State private var settings = AppSettings.shared

    var body: some Scene {
        // 菜单栏图标 → 玻璃快捷面板（参考图 4 右上），使用品牌光圈图标
        // 设置里关掉后入口消失，用 Dock 图标点开图库再进设置。
        if settings.showMenuBarIcon {
            MenuBarExtra {
                MenuBarPanelView()
            } label: {
                // 菜单栏状态项不能渲染自定义 Canvas 视图，使用预渲染的模板图。
                Image(nsImage: LensoStatusIcon.image)
                    .renderingMode(.template)
                    .frame(width: 18, height: 18)
            }
            .menuBarExtraStyle(.window)
        }

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
    static let side: CGFloat = 18

    static let image: NSImage = {
        let pointSize = NSSize(width: side, height: side)
        let image = NSImage(size: pointSize)

        // 以 2x 位图渲染，Retina 屏幕上保持清晰。
        let scale: CGFloat = 2
        let pixelSize = Int(side * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return image }

        rep.size = pointSize
        image.addRepresentation(rep)

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context

        let cg = context.cgContext
        // SwiftUI Canvas 使用左上角原点、y 向下的坐标系；这里做同样的翻转。
        cg.translateBy(x: 0, y: pointSize.height)
        cg.scaleBy(x: 1, y: -1)

        let center = CGPoint(x: pointSize.width / 2, y: pointSize.height / 2)
        let outerRadius = side * 0.34
        let innerRadius = side * 0.13
        let strokeWidth = side * 0.13

        // 模板图只使用 alpha 通道，黑色即可适配浅色/深色菜单栏。
        cg.setStrokeColor(NSColor.black.cgColor)
        cg.setFillColor(NSColor.black.cgColor)
        cg.setLineWidth(strokeWidth)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.setShouldAntialias(true)

        for (startAngle, endAngle) in [(100.0, 282.0), (292.0, 460.0)] {
            let path = CGMutablePath()
            path.addArc(
                center: center,
                radius: outerRadius,
                startAngle: CGFloat(startAngle) * .pi / 180,
                endAngle: CGFloat(endAngle) * .pi / 180,
                clockwise: false
            )
            cg.addPath(path)
            cg.strokePath()
        }

        cg.fillEllipse(in: CGRect(
            x: center.x - innerRadius,
            y: center.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        ))

        context.flushGraphics()
        image.isTemplate = true
        return image
    }()
}
