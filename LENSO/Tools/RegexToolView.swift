import SwiftUI
import AppKit
import Foundation

/// 正则测试工作台：实时匹配、替换与捕获组预览。
/// 输入超过 256 KB 自动停止实时计算，避免极端正则拖慢界面。
struct RegexToolView: View {
    @State private var pattern = ""
    @State private var input = ""
    @State private var replacement = ""
    @State private var mode: RegexMode = .match
    @State private var flags: RegexFlags = [.caseInsensitive]
    @State private var result: RegexEngine.Output = .empty
    @State private var pending: Task<Void, Never>?
    @State private var copied = false

    private let maxInputBytes = 256 * 1024

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                inputPane
                Divider().opacity(0.5)
                resultPane
            }
            Divider().opacity(0.5)
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: pattern) { _, _ in schedule() }
        .onChange(of: input) { _, _ in schedule() }
        .onChange(of: replacement) { _, _ in schedule() }
        .onChange(of: mode) { _, _ in schedule() }
        .onChange(of: flags) { _, _ in schedule() }
        .onDisappear { pending?.cancel() }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 9) {
                    LensoToolIcon(tool: ToolRegistry.shared.descriptor(for: "regex")!, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("正则测试")
                            .font(.system(size: 14, weight: .semibold))
                        Text("实时匹配 · 替换 · 捕获组")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Picker("", selection: $mode) {
                    ForEach(RegexMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 118)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "textformat.abc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("输入正则表达式", text: $pattern)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                flagToggle("i", help: "忽略大小写", flag: .caseInsensitive)
                flagToggle("m", help: "多行模式", flag: .anchorsMatchLines)
                flagToggle("s", help: "点匹配换行", flag: .dotMatchesLineSeparators)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func flagToggle(_ title: String, help: String, flag: RegexFlags) -> some View {
        let on = flags.contains(flag)
        return Button {
            if on { flags.remove(flag) } else { flags.insert(flag) }
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(on ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? LensoColors.kleinBlueBright : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 输入区

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("测试文本")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(input.isEmpty ? "粘贴一段文本" : "\(input.count) 字符")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            TextEditor(text: $input)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)

            if mode == .replace {
                Divider().opacity(0.5)
                HStack(spacing: 6) {
                    Text("替换为")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("$1 或替换文本", text: $replacement)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 结果区

    private var resultPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(mode == .replace ? "替换结果" : "匹配结果")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if mode == .replace {
                    Button {
                        copy(result.replaced ?? "")
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .disabled(result.replaced == nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            ScrollView {
                if let error = result.errorText {
                    notice(error, color: .orange, symbol: "exclamationmark.triangle.fill")
                        .padding(10)
                } else if !pattern.isEmpty && result.matches.isEmpty {
                    notice("没有匹配结果", color: .secondary, symbol: "circle.dashed")
                        .padding(10)
                } else if mode == .replace {
                    Text(result.replaced ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(result.matches.enumerated()), id: \.offset) { index, match in
                            matchRow(index: index, match: match)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func matchRow(index: Int, match: RegexEngine.Match) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("#\(index + 1)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(match.text.isEmpty ? "（空匹配）" : match.text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(2)
                Spacer()
                Text("位置 \(match.location)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if !match.groups.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(match.groups.enumerated()), id: \.offset) { groupIndex, value in
                        Text("$\(groupIndex + 1) \(value ?? "—")")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private func notice(_ text: String, color: Color, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: 10) {
            if result.errorText != nil {
                Label("正则有误", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            } else if result.tooLarge {
                Label("文本过大，已暂停实时计算", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if pattern.isEmpty {
                Text("输入正则后开始匹配")
            } else {
                Label("\(result.matches.count) 处匹配", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(result.matches.isEmpty ? Color.secondary : .green)
                Text("耗时 \(result.elapsedMilliseconds) ms")
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("i 忽略大小写 · m 多行 · s 点匹配换行")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - 计算

    private func schedule() {
        pending?.cancel()

        guard !pattern.isEmpty else {
            result = .empty
            return
        }
        if input.utf8.count > maxInputBytes {
            result = .init(matches: [], replaced: nil, errorText: nil, elapsedMilliseconds: 0, tooLarge: true)
            return
        }

        let pattern = pattern
        let input = input
        let replacement = replacement
        let mode = mode
        let flags = flags

        pending = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            let output = await Task.detached(priority: .userInitiated) {
                RegexEngine.process(
                    pattern: pattern,
                    input: input,
                    replacement: replacement,
                    mode: mode,
                    flags: flags
                )
            }.value

            guard !Task.isCancelled else { return }
            result = output
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            copied = false
        }
    }
}

enum RegexMode: String, CaseIterable, Identifiable, Sendable {
    case match = "匹配"
    case replace = "替换"
    var id: String { rawValue }
}

struct RegexFlags: OptionSet, Sendable {
    let rawValue: UInt
    static let caseInsensitive = RegexFlags(rawValue: 1 << 0)
    static let anchorsMatchLines = RegexFlags(rawValue: 1 << 1)
    static let dotMatchesLineSeparators = RegexFlags(rawValue: 1 << 2)
}

enum RegexEngine {
    struct Match: Sendable {
        let text: String
        let location: Int
        let groups: [String?]
    }

    struct Output: Sendable {
        let matches: [Match]
        let replaced: String?
        let errorText: String?
        let elapsedMilliseconds: Int
        let tooLarge: Bool

        static let empty = Output(
            matches: [], replaced: nil, errorText: nil,
            elapsedMilliseconds: 0, tooLarge: false
        )
    }

    static func process(
        pattern: String,
        input: String,
        replacement: String,
        mode: RegexMode,
        flags: RegexFlags
    ) -> Output {
        var options: NSRegularExpression.Options = []
        if flags.contains(.caseInsensitive) { options.insert(.caseInsensitive) }
        if flags.contains(.anchorsMatchLines) { options.insert(.anchorsMatchLines) }
        if flags.contains(.dotMatchesLineSeparators) { options.insert(.dotMatchesLineSeparators) }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            return Output(
                matches: [], replaced: nil,
                errorText: (error as NSError).localizedDescription,
                elapsedMilliseconds: 0, tooLarge: false
            )
        }

        let nsInput = input as NSString
        let fullRange = NSRange(location: 0, length: nsInput.length)
        let start = CFAbsoluteTimeGetCurrent()
        let rawMatches = regex.matches(in: input, options: [], range: fullRange)
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        var matches: [Match] = []
        matches.reserveCapacity(min(rawMatches.count, 500))

        for match in rawMatches.prefix(500) {
            var groups: [String?] = []
            if match.numberOfRanges > 1 {
                for index in 1..<match.numberOfRanges {
                    let range = match.range(at: index)
                    groups.append(range.location == NSNotFound ? nil : nsInput.substring(with: range))
                }
            }
            matches.append(
                Match(
                    text: nsInput.substring(with: match.range),
                    location: match.range.location,
                    groups: groups
                )
            )
        }

        let replaced: String?
        if mode == .replace {
            replaced = regex.stringByReplacingMatches(
                in: input,
                options: [],
                range: fullRange,
                withTemplate: replacement
            )
        } else {
            replaced = nil
        }

        return Output(
            matches: matches,
            replaced: replaced,
            errorText: nil,
            elapsedMilliseconds: elapsed,
            tooLarge: false
        )
    }
}
