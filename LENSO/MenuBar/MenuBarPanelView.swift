import SwiftUI

/// 菜单栏快捷面板（参考图 4 右上方）：
/// 四个入口：截图 / 图库 / 搜索 / 设置 — 图标在上、文字在下，玻璃材质，悬停反馈
struct MenuBarPanelView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var hoverID: String?

    private let entries: [Entry] = [
        Entry(id: "capture", icon: "viewfinder", label: "截图"),
        Entry(id: "library", icon: "photo.on.rectangle.angled", label: "图库"),
        Entry(id: "search", icon: "magnifyingglass", label: "搜索"),
        Entry(id: "settings", icon: "gearshape", label: "设置"),
    ]

    struct Entry: Identifiable {
        let id: String
        let icon: String
        let label: String
    }

    var body: some View {
        LensoMaterials.glassContainer {
            HStack(spacing: 10) {
                ForEach(entries) { entry in
                    MenuEntry(icon: entry.icon, label: entry.label, id: entry.id, hoverID: $hoverID) {
                        handle(entry.id)
                    }
                }
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(6)
        .frame(width: 312)
        .lensoColorScheme()
        .onReceive(NotificationCenter.default.publisher(for: .openPreviewForScreenshot)) { note in
            // “截图后显示预览”开着时，保存完成后自动打开预览窗口
            guard let id = note.object as? UUID else { return }
            openWindow(id: "preview", value: id)
        }
    }

    private func handle(_ id: String) {
        switch id {
        case "capture":
            CaptureCoordinator.shared.startRegionCapture()
        case "library":
            openWindow(id: "library")
            NSApp.activate(ignoringOtherApps: true)
        case "search":
            SearchPanelController.shared.show()
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
    let id: String
    @Binding var hoverID: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hoverID == id ? Color(nsColor: .controlAccentColor).opacity(0.85) : Color.primary.opacity(0.06))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(hoverID == id ? .white : .primary)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 64, height: 82)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoverID = hovering ? id : nil
        }
        .onTapGesture { action() }
        .animation(LensoAnimations.hover, value: hoverID)
    }
}
