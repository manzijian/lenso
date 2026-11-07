import SwiftUI

/// 设置窗口（参考图 4 左下）：左侧分类 + 右侧分组开关，浅色玻璃
struct SettingsWindowView: View {
    @State private var category: Category = .general
    @State private var shortcutStore = ShortcutStore.shared
    @State private var settings = AppSettings.shared

    enum Category: String, CaseIterable, Identifiable {
        case general = "通用"
        case capture = "截图"
        case shortcuts = "快捷键"
        case appearance = "外观"
        case about = "关于"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .capture: "viewfinder"
            case .shortcuts: "keyboard"
            case .appearance: "paintpalette"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(category.rawValue)
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.top, 24)
                    content
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.96, blue: 1.0), Color(red: 0.89, green: 0.91, blue: 0.99)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .lensoColorScheme()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Category.allCases) { c in
                HStack(spacing: 8) {
                    Image(systemName: c.icon)
                        .font(.system(size: 13))
                        .frame(width: 18)
                    Text(c.rawValue).font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(category == c ? Color.blue : .primary.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    if category == c {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(.white.opacity(0.6))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { category = c }
            }
            Spacer()
        }
        .padding(12)
        .padding(.top, 12)
        .frame(width: 150)
        .background(Color.white.opacity(0.25))
    }

    @ViewBuilder
    private var content: some View {
        switch category {
        case .general:
            VStack(spacing: 0) {
                SettingToggleRow(label: "开机启动 LENSO", isOn: $settings.launchAtLogin)
                Divider().padding(.leading, 14)
                SettingToggleRow(label: "在菜单栏显示图标", isOn: $settings.showMenuBarIcon)
                Divider().padding(.leading, 14)
                SettingToggleRow(label: "截图后显示预览", isOn: $settings.showPreviewAfterCapture)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(settings.glassEffect ? .white.opacity(0.55) : .white.opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.6), lineWidth: 1))
        case .capture:
            VStack(spacing: 0) {
                SettingToggleRow(label: "截图后自动复制到剪贴板", isOn: $settings.autoCopyAfterCapture)
                Divider().padding(.leading, 14)
                SettingToggleRow(label: "显示浮动预览", isOn: $settings.showFloatingPreview)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(settings.glassEffect ? .white.opacity(0.55) : .white.opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.6), lineWidth: 1))
        case .shortcuts:
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(ShortcutAction.allCases) { action in
                        SettingShortcutRow(action: action, store: shortcutStore)
                        if action != ShortcutAction.allCases.last {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(settings.glassEffect ? .white.opacity(0.55) : .white.opacity(0.95)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.6), lineWidth: 1))

                Button {
                    shortcutStore.resetAll()
                } label: {
                    Text("恢复默认")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(settings.glassEffect ? .white.opacity(0.55) : .white.opacity(0.95)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        case .appearance:
            VStack(spacing: 0) {
                SettingToggleRow(label: "跟随系统外观", isOn: $settings.followSystemAppearance)
                Divider().padding(.leading, 14)
                SettingToggleRow(label: "玻璃材质效果", isOn: $settings.glassEffect)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(settings.glassEffect ? .white.opacity(0.55) : .white.opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.6), lineWidth: 1))
        case .about:
            VStack(alignment: .leading, spacing: 6) {
                Text("LENSO").font(.system(size: 20, weight: .bold))
                Text("版本 1.0 · macOS 26").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("原生截图与图片管理工具").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(settings.glassEffect ? .white.opacity(0.55) : .white.opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.6), lineWidth: 1))
        }
    }

}

private struct SettingToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct SettingInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct SettingShortcutRow: View {
    let action: ShortcutAction
    let store: ShortcutStore

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: action.icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(action.title).font(.system(size: 13))
            Spacer()
            ShortcutRecorderView(action: action, store: store)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
