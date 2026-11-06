import SwiftUI

/// 设置窗口 — 左侧分类 + 右侧分组设置项，原生开关，无复杂装饰
struct SettingsWindowView: View {
    @State private var category: Category = .capture

    enum Category: String, CaseIterable, Identifiable {
        case capture = "截图"
        case classification = "智能分类"
        case permissions = "权限"
        case general = "通用"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .capture: "camera.viewfinder"
            case .classification: "tag"
            case .permissions: "lock.shield"
            case .general: "switch.2"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $category) {
                ForEach(Category.allCases) { c in
                    Label(c.rawValue, systemImage: c.icon).tag(c)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Group {
                switch category {
                case .capture: CaptureSettings()
                case .classification: ClassificationSettings()
                case .permissions: PermissionSettings()
                case .general: GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(LensoAmbientBackground())
    }
}

private struct SettingGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(LensoTypography.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, LensoSpacing.s)
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: LensoRadius.control)
                    .fill(.background.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LensoRadius.control)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
            )
        }
        .padding(LensoSpacing.xl)
        .frame(maxWidth: 560, alignment: .leading)
    }
}

private struct SettingRow: View {
    let label: String
    var description: String? = nil
    @ViewBuilder let trailing: () -> any View

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(LensoTypography.body)
                if let description {
                    Text(description).font(LensoTypography.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            AnyView(trailing())
        }
        .padding(.horizontal, LensoSpacing.l)
        .padding(.vertical, LensoSpacing.m)
    }
}

private struct ToggleRow: View {
    let label: String
    var description: String? = nil
    var initiallyOn = false
    @State private var isOn = false

    var body: some View {
        SettingRow(label: label, description: description) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
        Divider().padding(.leading, LensoSpacing.l)
        .onAppear { isOn = initiallyOn }
    }
}

private struct CaptureSettings: View {
    @State private var format = "PNG"

    var body: some View {
        ScrollView {
            SettingGroup(title: "截图") {
                ToggleRow(label: "截图后自动复制到剪贴板", initiallyOn: true)
                SettingRow(label: "默认保存格式") {
                    Picker("", selection: $format) {
                        Text("PNG").tag("PNG"); Text("HEIF").tag("HEIF"); Text("JPEG").tag("JPEG")
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                Divider().padding(.leading, LensoSpacing.l)
                ToggleRow(label: "浮动预览", description: "截图完成后显示预览窗口")
            }
        }
    }
}

private struct ClassificationSettings: View {
    var body: some View {
        ScrollView {
            SettingGroup(title: "智能分类") {
                ToggleRow(label: "自动标签（基于来源应用）", description: "根据截图来源应用推荐标签", initiallyOn: true)
                ToggleRow(label: "自动标签（基于 OCR 内容）", description: "识别截图文字后推荐标签")
            }
        }
    }
}

private struct PermissionSettings: View {
    var body: some View {
        ScrollView {
            SettingGroup(title: "权限") {
                SettingRow(label: "屏幕录制", description: "截图功能必需") {
                    Label("已授权", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(LensoTypography.callout)
                }
                Divider().padding(.leading, LensoSpacing.l)
                SettingRow(label: "通知") {
                    Button("去开启") { }
                        .controlSize(.small)
                }
            }
        }
    }
}

private struct GeneralSettings: View {
    @State private var launchAtLogin = false

    var body: some View {
        ScrollView {
            SettingGroup(title: "通用") {
                ToggleRow(label: "登录时启动")
                SettingRow(label: "检查更新") {
                    Text("V1.0").font(LensoTypography.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}
