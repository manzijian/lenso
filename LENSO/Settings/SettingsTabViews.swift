import SwiftUI
import AppKit

/// 设置卡片外框容器
struct SettingCardContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 4, y: 1)
        )
    }
}

/// 开关设置行
struct SettingToggleRow: View {
    let label: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.9))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(LensoColors.kleinBlueBright)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

/// 快捷键配置行
struct SettingShortcutRow: View {
    let action: ShortcutAction
    let store: ShortcutStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .frame(width: 18)

            Text(action.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.9))

            Spacer()

            ShortcutRecorderView(action: action, store: store)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

/// MCP 服务设置页签
struct MCPSettingsSectionView: View {
    private var agentGuidePrompt: String {
        """
        请在你的 MCP 配置中添加本地 LENSO 剪贴板与截图服务：

        {
          "mcpServers": {
            "lenso": {
              "url": "http://127.0.0.1:52888/sse"
            }
          }
        }

        配置完成后，你即可在对话中随时调用 LENSO 提供的工具，读取我最近复制的文字、截图历史及收纳便签。
        """
    }

    private var sseJsonConfig: String {
        LensoLocalService.shared.claudeDesktopConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 服务状态卡片
            SettingCardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("MCP 本地服务已就绪")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                        Spacer()
                        Text("MCP over SSE")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(LensoColors.kleinBlueSoft))
                    }

                    Text("LENSO 内置标准的 Model Context Protocol (MCP) 服务。无需配置复杂的系统二进制文件路径，AI Agent（如 Cursor、Claude Desktop、Windsurf、Antigravity 等）只需通过本地 MCP 地址即可直接挂载连接。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    Divider().opacity(0.6)

                    HStack(spacing: 8) {
                        Text("MCP 服务地址:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.75))
                        Text("http://127.0.0.1:52888/sse")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }

            // 专属一键引导卡片
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("让 Agent 自动连接的引导命令", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.85))
                    Spacer()
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(agentGuidePrompt, forType: .string)
                        SaveToastController.shared.show(title: "已复制 Agent 引导指令", subtitle: "直接粘贴发送给任意 AI 对话框即可", thumbnail: nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc.fill")
                            Text("一键复制 Agent 引导指令")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(LensoColors.kleinBlueBright))
                    }
                    .buttonStyle(.plain)
                }

                SettingCardContainer {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(agentGuidePrompt)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                    }
                    .padding(14)
                }
            }

            // JSON 配置文件
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Claude Desktop / MCP 客户端配置")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.85))
                    Spacer()
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(sseJsonConfig, forType: .string)
                        SaveToastController.shared.show(title: "已复制 MCP 配置 JSON", subtitle: "可粘贴至 Claude / Cursor 的 mcpServers 中", thumbnail: nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("复制 JSON")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(LensoColors.kleinBlueSoft))
                    }
                    .buttonStyle(.plain)
                }

                SettingCardContainer {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sseJsonConfig)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .textSelection(.enabled)
                    }
                    .padding(14)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("已开放的 MCP 工具列表 (Tools)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))

                SettingCardContainer {
                    VStack(spacing: 0) {
                        mcpToolRow(name: "lenso_get_recent_clipboard", desc: "读取最近复制的图文记录 (支持条数与类型过滤)")
                        toolDivider
                        mcpToolRow(name: "lenso_search_history", desc: "全局检索剪贴板内容、截图记录与文字收纳")
                        toolDivider
                        mcpToolRow(name: "lenso_get_latest_screenshot", desc: "获取最新一张截图的元数据与本地文件绝对路径")
                        toolDivider
                        mcpToolRow(name: "lenso_copy_text", desc: "写入文本至系统剪贴板并归集到 LENSO 历史")
                        toolDivider
                        mcpToolRow(name: "lenso_add_text_note", desc: "向文字收纳库保存一条新便签")
                    }
                }
            }
        }
    }

    private var toolDivider: some View {
        Divider()
            .padding(.leading, 14)
            .opacity(0.6)
    }

    private func mcpToolRow(name: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 12))
                .foregroundStyle(LensoColors.kleinBlueBright)
                .frame(width: 22, height: 22)
                .background(Circle().fill(LensoColors.kleinBlueSoft))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.9))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
