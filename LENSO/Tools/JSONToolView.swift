import AppKit
import SwiftUI

/// JSON 工作台：编辑 / 树 / 表格 / 类型 四种视图，
/// 自动校验 + 后台解析 + 语法着色，超过 4 MB 暂停处理以保持流畅。
struct JSONToolView: View {
    var initialText: String? = nil
    @State private var model = JSONWorkbenchModel()
    @State private var hoveredAction: JSONAction?

    var body: some View {
        VStack(spacing: 0) {
            header
            toolbar
            Divider().opacity(0.35)
            HStack(spacing: 10) {
                inputCard
                resultCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
        }
        .background(background)
        .frame(minWidth: 680, minHeight: 460)
        .lensoColorScheme()
        .onAppear {
            if let initialText, model.input.isEmpty {
                model.input = initialText
            }
        }
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    LensoColors.kleinBlueBright.opacity(0.045),
                    Color.clear,
                    LensoColors.kleinBlueBright.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 10) {
            if let tool = ToolRegistry.shared.descriptor(for: "json") {
                LensoToolIcon(tool: tool, size: 30)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("JSON 工作台")
                    .font(.system(size: 14, weight: .semibold))
                Text("格式化 · 校验 · 树 · 表格 · 类型")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.openFile()
            } label: {
                Label("打开", systemImage: "folder")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("o", modifiers: .command)

            Button {
                model.saveFile()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model.displayedOutput.isEmpty && model.input.isEmpty)

            Button {
                model.copyCurrent()
            } label: {
                Label(model.copied ? "已复制" : "复制结果",
                      systemImage: model.copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(LensoColors.kleinBlueBright)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!hasCopyableResult)
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    private var hasCopyableResult: Bool {
        switch model.viewMode {
        case .type: !model.types.isEmpty
        case .table: !(model.table?.rows.isEmpty ?? true)
        case .tree, .edit: !model.displayedOutput.isEmpty
        }
    }

    // MARK: - 工具条

    private var toolbar: some View {
        HStack(spacing: 10) {
            viewModePicker
            Spacer(minLength: 8)
            actionGroup
            Divider().frame(height: 16)
            indentMenu
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var viewModePicker: some View {
        HStack(spacing: 2) {
            ForEach(JSONViewMode.allCases) { mode in
                let selected = model.viewMode == mode
                Button {
                    model.viewMode = mode
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.62))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(LensoColors.accentGradient)
                                .shadow(color: LensoColors.kleinBlueBright.opacity(0.28), radius: 3, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.16), value: model.viewMode)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.045))
        )
    }

    private var actionGroup: some View {
        HStack(spacing: 1) {
            ForEach(JSONAction.allCases) { action in
                let hovered = hoveredAction == action
                Button {
                    model.perform(action)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 9.5, weight: .medium))
                        Text(action.rawValue)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(hovered ? LensoColors.kleinBlueBright : Color.primary.opacity(0.66))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(hovered ? LensoColors.kleinBlueSoft : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredAction = hovering ? action : nil
                }
                .help(actionHelp(action))
                .disabled(!model.hasInput)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.035))
        )
    }

    private func actionHelp(_ action: JSONAction) -> String {
        switch action {
        case .compress: "去掉所有空白，生成紧凑 JSON"
        case .sort: "递归按字段名排序后重新格式化"
        case .escape: "把当前内容转成 JSON 字符串字面量"
        case .unescape: "还原被转义的 JSON 字符串"
        }
    }

    private var indentMenu: some View {
        Menu {
            ForEach(JSONIndent.allCases) { item in
                Button {
                    model.indent = item
                } label: {
                    if model.indent == item {
                        Label(item.rawValue, systemImage: "checkmark")
                    } else {
                        Text(item.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 9.5))
                Text(model.indent.rawValue)
                    .font(.system(size: 10.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.035))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - 输入

    private var inputCard: some View {
        VStack(spacing: 0) {
            paneHeader(
                symbol: "square.and.pencil",
                title: "输入",
                detail: inputDetail
            ) {
                PaneIconButton(symbol: "doc.on.clipboard", help: "从剪贴板粘贴") {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        model.paste(string)
                    }
                }
                PaneIconButton(symbol: "trash", help: "清空输入") {
                    model.clear()
                }
                .disabled(model.input.isEmpty)
            }

            Divider().opacity(0.3)

            ZStack(alignment: .topLeading) {
                if model.input.isEmpty {
                    Text("在这里粘贴 JSON…")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: Binding(
                    get: { model.input },
                    set: { model.input = $0 }
                ))
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
    }

    private var inputDetail: String {
        guard !model.input.isEmpty else { return "等待输入" }
        let bytes = model.input.utf8.count
        return "\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) · \(lineCount(model.input)) 行"
    }

    // MARK: - 结果

    private var resultCard: some View {
        VStack(spacing: 0) {
            paneHeader(
                symbol: model.viewMode.symbol,
                title: "结果 · \(model.viewMode.rawValue)",
                detail: resultDetail
            ) {
                if model.isWorking {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.8)
                }
                if let label = model.actionLabel {
                    HStack(spacing: 3) {
                        Text("已\(label)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                        Button {
                            model.resetAction()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(LensoColors.kleinBlueBright)
                        }
                        .buttonStyle(.plain)
                        .help("恢复到自动格式化结果")
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(LensoColors.kleinBlueSoft))
                }
                PaneIconButton(symbol: model.copied ? "checkmark" : "doc.on.doc",
                               help: "复制结果") {
                    model.copyCurrent()
                }
                .disabled(!hasCopyableResult)
            }

            Divider().opacity(0.3)

            resultContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
    }

    private var resultDetail: String {
        if let label = model.actionLabel { return "\(label)结果" }
        guard let metrics = model.metrics, model.error == nil else { return " " }
        return "\(metrics.nodes) 节点 · \(metrics.lines) 行"
    }

    @ViewBuilder
    private var resultContent: some View {
        if let error = model.error {
            JSONErrorView(error: error)
        } else if !model.hasInput {
            JSONEmptyState(
                symbol: "curlybraces",
                title: "还没有内容",
                subtitle: "左侧粘贴 JSON 后会自动格式化、校验，并同步生成树、表格与 TypeScript 类型。",
                actionTitle: "载入示例",
                action: { model.loadSample() }
            )
        } else {
            switch model.viewMode {
            case .edit:
                editResult
            case .tree:
                if let tree = model.tree {
                    JSONTreeResultView(root: tree)
                } else {
                    placeholder("list.bullet.indent", "正在生成树结构…")
                }
            case .table:
                if let table = model.table {
                    JSONTableResultView(table: table)
                } else {
                    placeholder("tablecells", "正在生成表格…")
                }
            case .type:
                if model.types.isEmpty {
                    placeholder("curlybraces.square", "正在生成 TypeScript 类型…")
                } else {
                    JSONTypeResultView(types: model.types)
                }
            }
        }
    }

    private var editResult: some View {
        ScrollView {
            if model.actionLabel == nil, let highlighted = model.highlighted {
                Text(highlighted)
                    .font(.system(size: 12.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
            } else {
                Text(model.displayedOutput)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 通用组件

    private func paneHeader<Trailing: View>(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(LensoColors.kleinBlueBright.opacity(0.75))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.62))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.055), lineWidth: 0.5)
            )
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(model.statusText)
                .foregroundStyle(model.error == nil ? Color.primary.opacity(0.65) : statusColor)

            if let metrics = model.metrics, model.error == nil {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(metrics.nodes) 节点")
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(byteText(metrics.inputBytes)) → \(byteText(metrics.outputBytes))")
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(metrics.lines) 行")
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(metrics.durationMS) ms")
            }

            Spacer()

            Text("⌘O 打开 · ⌘S 保存 · ⇧⌘C 复制")
                .foregroundStyle(.tertiary)

            if model.isWorking {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.015))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.black.opacity(0.05)).frame(height: 0.5)
        }
    }

    private var statusColor: Color {
        if let error = model.error { return error.fatal ? .orange : .red }
        return model.hasInput ? .green : .secondary.opacity(0.5)
    }

    // MARK: - 工具函数

    private func lineCount(_ text: String) -> Int {
        text.reduce(into: 1) { partial, char in if char == "\n" { partial += 1 } }
    }

    private func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - 小按钮

private struct PaneIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(hovering ? LensoColors.kleinBlueBright : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? LensoColors.kleinBlueSoft : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
