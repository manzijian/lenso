import SwiftUI

/// 菜单栏快捷面板 — 四个入口，图标上文字下，玻璃材质
struct MenuBarPanelView: View {
    @State private var hoverID: String?

    private let entries: [(id: String, icon: String, label: String)] = [
        ("region", "rectangle.dashed", "区域截图"),
        ("window", "macwindow.on.rectangle", "窗口截图"),
        ("library", "photo.on.rectangle.angled", "图库"),
        ("settings", "gearshape", "设置"),
    ]

    var body: some View {
        LensoMaterials.glassContainer {
            HStack(spacing: LensoSpacing.m) {
                ForEach(entries, id: \.id) { entry in
                    MenuEntry(icon: entry.icon, label: entry.label, id: entry.id, hoverID: $hoverID)
                }
            }
            .padding(LensoSpacing.l)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LensoRadius.panel))
        }
        .padding(LensoSpacing.m)
        .frame(width: 320)
        .background(LensoAmbientBackground())
    }
}

private struct MenuEntry: View {
    let icon: String
    let label: String
    let id: String
    @Binding var hoverID: String?

    var body: some View {
        VStack(spacing: LensoSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(hoverID == id ? LensoColors.accent : .primary)
            Text(label)
                .font(LensoTypography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 64, height: 64)
        .background {
            RoundedRectangle(cornerRadius: LensoRadius.control)
                .fill(LensoColors.accent.opacity(hoverID == id ? 0.14 : 0))
        }
        .onHover { hovering in
            hoverID = hovering ? id : nil
        }
        .animation(LensoAnimations.hover, value: hoverID)
    }
}
