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
    @State private var settings = AppSettings.shared
    @State private var usageEntries: [MCPUsageLog.Entry] = []
    @State private var confirmClearUsageLog = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // 开关控制卡片
            SettingCardContainer {
                SettingToggleRow(
                    label: "开启 MCP 本地服务",
                    subtitle: "允许本地 AI Agent（Claude、Cursor、Antigravity 等）安全调用剪贴板与截图工具",
                    isOn: $settings.enableMCPServer
                )
            }

            // 服务状态卡片
            SettingCardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(settings.enableMCPServer ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(settings.enableMCPServer ? "MCP 本地服务运行中" : "MCP 本地服务已关闭")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(settings.enableMCPServer ? LensoColors.kleinBlueBright : Color.secondary)
                        Spacer()
                        Text(settings.enableMCPServer ? "127.0.0.1:52888" : "已离线")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(settings.enableMCPServer ? LensoColors.kleinBlueBright : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(settings.enableMCPServer ? LensoColors.kleinBlueSoft : Color.black.opacity(0.04)))
                    }

                    if settings.enableMCPServer {
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
                    } else {
                        Text("本地 52888 端口监听已停止并完全释放。外部 AI 客户端将无法连接或读取剪贴板与截图数据。随时可重新打开上方开关以恢复连接。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                }
                .padding(16)
                .lensoAnimation(LensoAnimations.panel, value: settings.enableMCPServer, reduceMotion: reduceMotion)
            }

            if settings.enableMCPServer {
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
                        .buttonStyle(LensoPressButtonStyle())
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
                .transition(LensoTransitions.inlineExpand(reduceMotion: reduceMotion))

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
                        .buttonStyle(LensoPressButtonStyle())
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
                .transition(LensoTransitions.inlineExpand(reduceMotion: reduceMotion))

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
                .transition(LensoTransitions.inlineExpand(reduceMotion: reduceMotion))
            }

            usageLogSection
        }
        .lensoAnimation(LensoAnimations.panel, value: settings.enableMCPServer, reduceMotion: reduceMotion)
        .onAppear { refreshUsageLog() }
        .onReceive(NotificationCenter.default.publisher(for: .mcpUsageLogDidChange)) { _ in
            usageEntries = MCPUsageLog.shared.snapshot()
        }
    }

    // MARK: - 使用记录

    private var usageLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("MCP 使用记录")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))

                Text("\(usageEntries.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LensoColors.kleinBlueBright)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(LensoColors.kleinBlueSoft))
                    .lensoNumericTransition()

                Spacer()

                UsageIconButton(symbol: "folder", help: "在 Finder 中显示日志") {
                    let url = MCPUsageLog.shared.fileURL
                    if FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        NSWorkspace.shared.open(url.deletingLastPathComponent())
                    }
                }

                UsageIconButton(symbol: "trash", help: "清空使用记录", enabled: !usageEntries.isEmpty) {
                    confirmClearUsageLog = true
                }
                .confirmationDialog(
                    "确认清空 MCP 使用记录？",
                    isPresented: $confirmClearUsageLog,
                    titleVisibility: .visible
                ) {
                    Button("清空记录", role: .destructive) {
                        MCPUsageLog.shared.clear()
                        usageEntries = []
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("本地调用日志将被清空，此操作不可撤销。")
                }
            }

            SettingCardContainer {
                VStack(spacing: 0) {
                    if usageEntries.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 16, weight: .light))
                                .foregroundStyle(LensoColors.kleinBlueBright.opacity(0.55))
                            Text("暂无调用记录")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("AI Agent 调用工具后，会实时出现在这里")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                    } else {
                        if !todayUsage.isEmpty {
                            usageSummaryStrip
                            Divider().opacity(0.4)
                        }

                        let visible = Array(usageEntries.prefix(10))
                        ForEach(visible) { entry in
                            MCPUsageLogRow(entry: entry)
                            if entry.id != visible.last?.id {
                                Divider().padding(.leading, 48).opacity(0.5)
                            }
                        }
                    }
                }
            }

            Text("列表展示最近 10 条 · 仅保留最近 200 条，数据只保存在本机。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private var todayUsage: [MCPUsageLog.Entry] {
        usageEntries.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var usageSummaryStrip: some View {
        let today = todayUsage
        let successCount = today.filter(\.success).count
        let rate = Int((Double(successCount) / Double(max(today.count, 1)) * 100).rounded())
        let average = today.reduce(0) { $0 + $1.durationMS } / max(today.count, 1)

        return HStack(spacing: 16) {
            summaryItem(label: "今日调用", value: "\(today.count)", unit: "次")
            Rectangle().fill(Color.black.opacity(0.06)).frame(width: 0.5, height: 12)
            summaryItem(label: "成功率", value: "\(rate)", unit: "%")
            Rectangle().fill(Color.black.opacity(0.06)).frame(width: 0.5, height: 12)
            summaryItem(label: "平均耗时", value: "\(average)", unit: "ms")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LensoColors.kleinBlueBright.opacity(0.032))
    }

    private func summaryItem(label: String, value: String, unit: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(LensoColors.kleinBlueBright)
                .lensoNumericTransition()
            Text(unit)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 行组件

    private struct UsageIconButton: View {
        let symbol: String
        let help: String
        var enabled: Bool = true
        let action: () -> Void
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.35))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(hovering && enabled
                                      ? LensoColors.kleinBlueSoft
                                      : Color.black.opacity(0.035))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(LensoPressButtonStyle(scale: 0.92))
            .disabled(!enabled)
            .onHover { hovering = $0 }
            .lensoAnimation(LensoAnimations.hover, value: hovering, reduceMotion: reduceMotion)
            .help(help)
        }
    }

    private struct MCPUsageLogRow: View {
        let entry: MCPUsageLog.Entry
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private static let todayFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()

        private static let fullFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M/d HH:mm:ss"
            return formatter
        }()

        var body: some View {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(entry.success ? LensoColors.kleinBlueSoft : Color.red.opacity(0.1))
                        .frame(width: 26, height: 26)
                    Image(systemName: symbol)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(entry.success ? LensoColors.kleinBlueBright : Color.red)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.88))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if !entry.success {
                            Text("失败")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.red.opacity(0.09)))
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(entry.durationMS) ms")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(hovering ? LensoColors.kleinBlueBright.opacity(0.045) : Color.clear)
            .onHover { hovering = $0 }
            .lensoAnimation(LensoAnimations.hover, value: hovering, reduceMotion: reduceMotion)
            .help(entry.detail ?? "")
        }

        private var symbol: String {
            switch entry.method {
            case "initialize": "bolt.horizontal.circle.fill"
            case "resources/read": "doc.text.fill"
            default: "wrench.and.screwdriver.fill"
            }
        }

        private var title: String {
            switch entry.method {
            case "initialize": "客户端连接"
            case "resources/read": entry.name.isEmpty ? "读取资源" : entry.name
            default: entry.name.isEmpty ? "工具调用" : entry.name
            }
        }

        private var subtitle: String {
            let client = (entry.client?.isEmpty == false ? entry.client! : "本机 Agent")
            let kind: String
            switch entry.method {
            case "initialize": kind = "建立连接"
            case "resources/read": kind = "读取资源"
            default: kind = "工具调用"
            }
            return "\(client) · \(kind)"
        }

        private var timeText: String {
            let formatter = Calendar.current.isDateInToday(entry.date)
                ? Self.todayFormatter
                : Self.fullFormatter
            return formatter.string(from: entry.date)
        }
    }

    private func refreshUsageLog() {
        MCPUsageLog.shared.reload()
        usageEntries = MCPUsageLog.shared.snapshot()
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
