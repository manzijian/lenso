import SwiftUI

/// 设置里的「工具目录」：内置插件化管理，安装 / 停用 / 卸载。
/// 截图内核固定内置，不可卸载。
struct ToolCatalogView: View {
    @State private var registry = ToolRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary

            VStack(spacing: 0) {
                ForEach(ToolRegistry.catalog) { tool in
                    ToolCatalogRow(tool: tool)
                    if tool.id != ToolRegistry.catalog.last?.id {
                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            )

            Text("工具随 LENSO 发布，安装或停用只影响状态栏面板与工作台入口，不会下载额外内容。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已安装 \(registry.installedCount) / \(ToolRegistry.catalog.filter(\.isAvailable).count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lensoNumericTransition()
                Text("安装后会在状态栏面板的「工具」分组中出现")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LensoColors.kleinBlueSoft)
        )
    }
}

private struct ToolCatalogRow: View {
    let tool: LensoToolDescriptor
    @State private var registry = ToolRegistry.shared
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var installed: Bool { registry.isInstalled(tool.id) }
    private var enabled: Bool { registry.isEnabled(tool.id) }

    var body: some View {
        HStack(spacing: 11) {
            LensoToolIcon(tool: tool, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                    if tool.isCore {
                        tag("内核", color: LensoColors.kleinBlueBright)
                    }
                    if !tool.isAvailable {
                        tag("即将上线", color: .gray)
                    }
                }
                Text(tool.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(tool.version) · \(tool.sizeText) · \(tool.group)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            action
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(hovering ? Color.black.opacity(0.025) : Color.clear)
        .onHover { hovering = $0 }
        .lensoAnimation(LensoAnimations.hover, value: hovering, reduceMotion: reduceMotion)
        .lensoAnimation(LensoAnimations.snappy, value: installed, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var action: some View {
        if tool.isCore {
            Text("固定内置")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        } else if !tool.isAvailable {
            Text("敬请期待")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.black.opacity(0.04))
                )
        } else if installed {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { registry.setEnabled(tool.id, $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(enabled ? "从面板隐藏" : "在面板显示")

                Button("卸载") {
                    LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                        registry.uninstall(tool.id)
                    }
                }
                .buttonStyle(LensoPressButtonStyle())
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.05)))
            }
        } else {
            Button {
                LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                    registry.install(tool.id)
                }
            } label: {
                Label("安装", systemImage: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5.5)
                    .background(
                        Capsule().fill(LensoColors.kleinBlueBright)
                    )
            }
            .buttonStyle(LensoPressButtonStyle())
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}
