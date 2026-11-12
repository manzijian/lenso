import SwiftUI

/// 菜单栏快捷面板：
/// 四个入口：截图 / 搜索 / 数据看板 / 设置 — 图标在上、文字与专属快捷键在下，玻璃材质，悬停反馈
struct MenuBarPanelView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var hoverID: String?
    @State private var shortcutStore = ShortcutStore.shared

    private let entries: [Entry] = [
        Entry(id: "capture", icon: "viewfinder", label: "截图", action: .captureRegion),
        Entry(id: "search", icon: "magnifyingglass", label: "搜索", action: .globalSearch),
        Entry(id: "analytics", icon: "chart.bar.xaxis", label: "数据看板", action: .openAnalytics),
        Entry(id: "settings", icon: "gearshape", label: "设置", action: .openSettings),
    ]

    struct Entry: Identifiable {
        let id: String
        let icon: String
        let label: String
        let action: ShortcutAction
    }

    var body: some View {
        LensoMaterials.glassContainer {
            HStack(spacing: 8) {
                ForEach(entries) { entry in
                    let combo = shortcutStore.combo(for: entry.action)
                    MenuEntry(
                        icon: entry.icon,
                        label: entry.label,
                        shortcut: combo.displayString,
                        id: entry.id,
                        hoverID: $hoverID
                    ) {
                        handle(entry.id)
                    }
                }
            }
            .padding(10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(6)
        .frame(width: 320)
        .lensoColorScheme()
        .onReceive(NotificationCenter.default.publisher(for: .lensoShortcutsChanged)) { _ in
            shortcutStore = ShortcutStore.shared
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPreviewForScreenshot)) { note in
            // “截图后显示预览”开着时，使用纯粹浮动贴图浮现（回到刚截图的体验，杜绝大窗口包裹）
            guard let id = note.object as? UUID,
                  let record = (try? ScreenshotStore.shared.list())?.first(where: { $0.id == id }),
                  let cgImage = ScreenshotStore.shared.loadImage(record) else { return }
            CaptureCoordinator.shared.pin(image: cgImage, isPreview: true)
        }
    }

    private func handle(_ id: String) {
        switch id {
        case "capture":
            CaptureCoordinator.shared.startRegionCapture()
        case "search":
            SearchPanelController.shared.show()
        case "analytics":
            openWindow(id: "library")
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .openAnalyticsSection, object: nil)
        case "settings":
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        default:
            break
        }
        dismiss()
    }
}

private struct MenuEntry: View {
    let icon: String
    let label: String
    let shortcut: String
    let id: String
    @Binding var hoverID: String?
    let action: () -> Void

    var isHovered: Bool { hoverID == id }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isHovered ? Color(nsColor: .controlAccentColor).opacity(0.88) : Color.black.opacity(0.05))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isHovered ? .white : .primary)
            }

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered ? Color(nsColor: .controlAccentColor) : .primary)
                .lineLimit(1)

            // 下方对应的最新快捷键胶囊
            Text(shortcut)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.04))
                )
        }
        .frame(width: 68, height: 94)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoverID = hovering ? id : nil
        }
        .onTapGesture { action() }
        .animation(LensoAnimations.hover, value: hoverID)
    }
}
