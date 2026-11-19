import SwiftUI

// MARK: - 空状态 / 错误

struct JSONEmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(LensoColors.kleinBlueBright.opacity(0.55))
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(LensoColors.kleinBlueBright)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct JSONErrorView: View {
    let error: JSONErrorInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text(error.fatal ? "无法处理" : "JSON 语法错误")
                    .font(.system(size: 12.5, weight: .semibold))
                if let line = error.line, let column = error.column {
                    Text("第 \(line) 行 · 第 \(column) 列")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                }
                Spacer(minLength: 0)
            }
            Text(error.message)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.5)
        )
        .padding(10)
    }
}

// MARK: - 树视图

struct JSONTreeResultView: View {
    let root: JSONTreeNode

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(root.children ?? []) { node in
                    JSONTreeRow(node: node, depth: 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct JSONTreeRow: View {
    let node: JSONTreeNode
    let depth: Int
    @State private var expanded: Bool

    init(node: JSONTreeNode, depth: Int) {
        self.node = node
        self.depth = depth
        _expanded = State(initialValue: depth < 2)
    }

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(children) { child in
                        JSONTreeRow(node: child, depth: depth + 1)
                    }
                    if node.truncated {
                        Text("节点过多，已省略后续内容")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 18)
                            .padding(.top, 3)
                    }
                }
            } label: {
                rowLabel(count: children.count)
            }
        } else {
            rowLabel(count: nil)
        }
    }

    private func rowLabel(count: Int?) -> some View {
        HStack(spacing: 5) {
            if let key = node.key {
                Text(key)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(LensoColors.kleinBlueBright)
                Text(":")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if let count {
                Text(node.value.typeName)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("(\(count))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text(node.value.preview)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(color(for: node.value))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1.5)
        .contentShape(Rectangle())
    }

    private func color(for value: JSONValue) -> Color {
        switch value {
        case .string: Color(red: 0.10, green: 0.48, blue: 0.30)
        case .number: Color(red: 0.69, green: 0.30, blue: 0.10)
        case .bool, .null: Color(red: 0.47, green: 0.22, blue: 0.72)
        case .object, .array: .secondary
        }
    }
}

// MARK: - 表格视图

struct JSONTableResultView: View {
    let table: JSONTable

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(table.columns.enumerated()), id: \.offset) { index, column in
                        Text(column)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .frame(width: width(for: index), alignment: .leading)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(Color.black.opacity(0.05)).frame(width: 0.5)
                            }
                    }
                }
                .background(LensoColors.kleinBlueBright.opacity(0.055))

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                            Text(cell)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.86))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5.5)
                                .frame(width: width(for: index), alignment: .leading)
                                .overlay(alignment: .trailing) {
                                    Rectangle().fill(Color.black.opacity(0.04)).frame(width: 0.5)
                                }
                        }
                    }
                    .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.black.opacity(0.018))
                }

                if table.truncated {
                    Text("共 \(table.totalRows) 行，仅展示前 \(table.rows.count) 行")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func width(for index: Int) -> CGFloat {
        index == 0 ? 150 : 200
    }
}

// MARK: - 类型视图

struct JSONTypeResultView: View {
    let types: String

    var body: some View {
        ScrollView {
            Text(types)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
