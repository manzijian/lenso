import SwiftUI

// MARK: - 日分组标题（截图 / 最近 / 收藏 / 文字 共用）

enum LibraryDayLabel {
    static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let year = calendar.component(.year, from: day)
        let currentYear = calendar.component(.year, from: Date())
        formatter.dateFormat = (year == currentYear) ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: day)
    }
}

struct LibraryDayHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.7))

            Text("\(count)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lensoNumericTransition()
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.black.opacity(0.05)))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(red: 0.985, green: 0.988, blue: 0.995))
    }
}

// MARK: - 栏目内搜索框

struct LibrarySearchField: View {
    @Binding var text: String
    var prompt: String = "搜索当前栏目"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.7))

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
                .buttonStyle(LensoPressButtonStyle())
                .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }
        }
        .lensoAnimation(LensoAnimations.snappy, value: text.isEmpty, reduceMotion: reduceMotion)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
        )
    }
}

// MARK: - 文字便签的列表展示信息（最近 / 收藏 / 文字 共用）

@MainActor
enum TextNoteFace {
    static func typeInfo(_ type: TextIntelligence.ContentType) -> (icon: String, label: String) {
        switch type {
        case .url: return ("globe", "网页")
        case .json: return ("curlybraces", "JSON")
        case .code(let lang, _): return ("chevron.left.forwardslash.chevron.right", lang)
        case .plainText: return ("text.alignleft", "文字")
        }
    }

    static func title(for note: TextNote, type: TextIntelligence.ContentType) -> String {
        switch type {
        case .url(_, let original):
            return WebMetadataStore.shared.title(for: original)
                ?? URL(string: original)?.host
                ?? original
        case .json:
            return "JSON 数据"
        case .code(let lang, _):
            return "\(lang) 代码"
        case .plainText:
            let first = note.content.components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            return first.isEmpty ? "（空白）" : String(first.prefix(64))
        }
    }

    static func subtitle(for note: TextNote, type: TextIntelligence.ContentType) -> String {
        switch type {
        case .json(let pretty, _):
            return compact(pretty)
        case .code(_, let formatted):
            return compact(formatted)
        case .url(_, let original):
            return original
        case .plainText:
            let lines = note.content.components(separatedBy: .newlines)
            let rest = lines.dropFirst().joined(separator: " ")
            return compact(rest.isEmpty ? note.content : rest)
        }
    }

    static func compact(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func matches(_ note: TextNote, query: String) -> Bool {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return true }

        if note.content.localizedCaseInsensitiveContains(keyword) { return true }
        if let source = note.sourceApp, source.localizedCaseInsensitiveContains(keyword) { return true }

        let type = TextIntelligence.detect(note.content)
        return typeInfo(type).label.localizedCaseInsensitiveContains(keyword)
    }

    static func matches(_ entry: LibraryEntry, query: String) -> Bool {        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return true }

        if let note = entry.note {
            return matches(note, query: keyword)
        }
        if let record = entry.screenshot {
            let haystack = "\(record.filename) \(record.width) \(record.height) 截图"
            return haystack.localizedCaseInsensitiveContains(keyword)
        }
        return false
    }

    static func matches(_ entries: [LibraryEntry], query: String) -> [LibraryEntry] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return entries }
        return entries.filter { matches($0, query: keyword) }
    }

    static func matches(_ notes: [TextNote], query: String) -> [TextNote] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return notes }
        return notes.filter { matches($0, query: keyword) }
    }
}
