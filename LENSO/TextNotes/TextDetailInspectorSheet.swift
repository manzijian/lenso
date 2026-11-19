import SwiftUI
import AppKit

/// 文本详情查看器（检查器式布局）
/// 左侧阅读 / 右侧常驻元信息与显示方式，底部主操作常驻；
/// 正文采用限宽阅读栏，JSON 与代码保持全宽 + 行号。
struct TextDetailInspectorSheet: View {
    let rawContent: String
    let sourceApp: String?
    let createdAt: Date
    var onDismiss: () -> Void = {}

    @ObservedObject private var webStore = WebMetadataStore.shared
    @State private var contentType: TextIntelligence.ContentType = .plainText
    @State private var jsonMode: Int = 0 // 0: 美化, 1: 压缩, 2: 原始
    @State private var codeMode: Int = 0 // 0: 高亮排版, 1: 原始代码
    @State private var textMode: Int = 0 // 0: 自然排版, 1: 等宽排版
    @State private var copied: Bool = false
    @State private var searchQuery: String = ""

    private let pageBackground = Color(red: 0.973, green: 0.976, blue: 0.986)
    private let sidebarBackground = Color(red: 0.966, green: 0.970, blue: 0.982)
    private let hairline = Color.black.opacity(0.06)
    private let cardShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(hairline).frame(height: 0.5)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if case .url(let url, let originalStr) = contentType {
                        urlBannerCard(url: url, originalString: originalStr)
                    }

                    contentArea

                    Rectangle().fill(hairline).frame(height: 0.5)
                    footerBar
                }

                sidebar
            }
        }
        .frame(minWidth: 780, idealWidth: 880, maxWidth: 980, minHeight: 540, idealHeight: 600)
        .background(pageBackground)
        .onAppear {
            contentType = TextIntelligence.detect(rawContent)
            if case .url(_, let originalStr) = contentType {
                webStore.fetchTitleIfNeeded(for: originalStr)
            }
        }
        .lensoColorScheme()
    }

    // MARK: - 顶部栏

    private var headerBar: some View {
        HStack(spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: typeIcon)
                    .font(.system(size: 12, weight: .semibold))
                Text(typeTitle)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(LensoColors.kleinBlueBright)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(LensoColors.kleinBlueSoft))

            if let app = sourceApp, !app.isEmpty {
                Text(app)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.045)))
            }

            Spacer()

            Text(createdAt.lensoRelativeDayTime)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.42))

            searchField

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help("关闭 (Esc)")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.white)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField("搜索正文", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 112)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.045)))
    }

    // MARK: - 网页卡片

    private func urlBannerCard(url: URL, originalString: String) -> some View {
        let webTitle = webStore.title(for: originalString) ?? url.host ?? originalString

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LensoColors.kleinBlueSoft)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(webTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                        .lineLimit(1)
                    if let host = url.host {
                        Text(host)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(LensoColors.kleinBlueSoft))
                    }
                }
                Text(originalString)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 4) {
                    Text("打开")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(LensoColors.kleinBlueBright))
            }
            .buttonStyle(.plain)
            .help("在系统默认浏览器中打开")
        }
        .padding(12)
        .background(cardShape.fill(Color.white))
        .overlay(cardShape.strokeBorder(hairline, lineWidth: 0.8))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - 正文区

    private var contentArea: some View {
        Group {
            if isStructuredContent {
                // 代码 / JSON：长行保留行号对齐，允许横向滚动，不压缩排版
                ScrollView([.horizontal, .vertical]) {
                    structuredContent
                        .background(cardShape.fill(Color.white))
                        .overlay(cardShape.strokeBorder(hairline, lineWidth: 0.8))
                        .padding(18)
                }
            } else {
                // 普通文本：只做纵向滚动，正文始终在可视宽度内换行
                ScrollView(.vertical) {
                    readableContent
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 24)
                        .background(cardShape.fill(Color.white))
                        .overlay(cardShape.strokeBorder(hairline, lineWidth: 0.8))
                        .padding(18)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(pageBackground)
    }

    /// 普通文本 / 网页链接：限宽阅读栏
    private var readableContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = plainTitle {
                Text(searchHighlighted(AttributedString(title)))
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }

            Text(readableAttributed)
                .lineSpacing(textMode == 0 ? 6.5 : 5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    /// JSON / 代码：全宽 + 行号
    private var structuredContent: some View {
        HStack(alignment: .top, spacing: 0) {
            if shouldShowLineNumbers {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(1...max(1, displayedLinesCount), id: \.self) { line in
                        Text("\(line)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.25))
                            .frame(height: 21, alignment: .top)
                    }
                }
                .padding(.top, 14)
                .padding(.leading, 14)
                .padding(.trailing, 12)

                Rectangle().fill(hairline).frame(width: 0.5)
            }

            Text(structuredAttributed)
                .lineSpacing(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.vertical, 14)
                .padding(.leading, 14)
                .padding(.trailing, 18)
        }
    }

    // MARK: - 底部操作栏

    private var footerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("\(currentFormattedContent.count) 字符")
                Text("·").foregroundStyle(Color.secondary.opacity(0.4))
                Text("\(displayedLinesCount) 行")
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.45))

            Spacer()

            Button {
                _ = try? ScreenshotStore.shared.createTextNote(
                    content: currentFormattedContent,
                    sourceApp: sourceApp ?? "查看器"
                )
                SaveToastController.shared.show(title: "已保存为收纳便签", subtitle: "", thumbnail: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark")
                    Text("存为便签")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.72))
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(Capsule().fill(Color.black.opacity(0.045)))
            }
            .buttonStyle(.plain)
            .help("保存至文字收纳库")

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(currentFormattedContent, forType: .string)
                copied = true
                SaveToastController.shared.show(title: "已复制到剪贴板", subtitle: "", thumbnail: nil)
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    await MainActor.run { copied = false }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc.fill")
                    Text(copied ? "已复制" : "复制全部")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(copied ? Color(red: 0.11, green: 0.55, blue: 0.33) : LensoColors.kleinBlueBright))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(Color.white)
    }

    // MARK: - 右侧检查器

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sideLabel("元信息")
            metaRow("类型", typeTitle)
            metaRow("来源", (sourceApp?.isEmpty == false ? sourceApp! : "—"))
            metaRow("时间", createdAt.lensoRelativeDayTime)
            metaRow("字符", "\(currentFormattedContent.count)")
            metaRow("行数", "\(displayedLinesCount)")

            sideLabel("显示")
                .padding(.top, 20)
                .padding(.bottom, 4)

            VStack(spacing: 2) {
                ForEach(modeOptions) { option in
                    modeRow(option)
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 6) {
                Text("Esc")
                    .font(.system(size: 9.5, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.black.opacity(0.055)))
                    .foregroundStyle(Color.primary.opacity(0.55))
                Text("关闭")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: 190)
        .background(sidebarBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(hairline).frame(width: 0.5)
        }
    }

    private func sideLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.primary.opacity(0.35))
            .padding(.bottom, 6)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.45))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 6.5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(hairline).frame(height: 0.5)
        }
    }

    private func modeRow(_ option: ModeOption) -> some View {
        let selected = selectedMode == option.id
        return Button {
            selectMode(option.id)
        } label: {
            HStack(spacing: 6) {
                Text(option.title)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(selected ? LensoColors.kleinBlueBright : Color.primary.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? LensoColors.kleinBlueSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 显示模式

    private struct ModeOption: Identifiable {
        let id: Int
        let title: String
    }

    private var modeOptions: [ModeOption] {
        switch contentType {
        case .json:
            return [.init(id: 0, title: "美化"), .init(id: 1, title: "压缩"), .init(id: 2, title: "原始")]
        case .code:
            return [.init(id: 0, title: "语法高亮"), .init(id: 1, title: "原始代码")]
        case .url, .plainText:
            return [.init(id: 0, title: "自然排版"), .init(id: 1, title: "等宽")]
        }
    }

    private var selectedMode: Int {
        switch contentType {
        case .json: return jsonMode
        case .code: return codeMode
        case .url, .plainText: return textMode
        }
    }

    private func selectMode(_ id: Int) {
        switch contentType {
        case .json: jsonMode = id
        case .code: codeMode = id
        case .url, .plainText: textMode = id
        }
    }

    // MARK: - 正文内容构建

    private var isStructuredContent: Bool {
        switch contentType {
        case .json, .code: return true
        default: return false
        }
    }

    /// 纯文本首行提为标题（仅自然排版、且确实存在后续正文时）
    private var plainTitle: String? {
        splitPlainText.title
    }

    private var plainBody: String {
        splitPlainText.body
    }

    private var splitPlainText: (title: String?, body: String) {
        guard case .plainText = contentType, textMode == 0 else { return (nil, rawContent) }
        let lines = rawContent.components(separatedBy: .newlines)
        guard lines.count > 1 else { return (nil, rawContent) }

        let first = lines[0].trimmingCharacters(in: .whitespaces)
        guard first.count >= 4, first.count <= 64 else { return (nil, rawContent) }

        let rest = lines.dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return (nil, rawContent) }

        return (first, rest)
    }

    private var readableAttributed: AttributedString {
        let text: String
        switch contentType {
        case .plainText:
            text = textMode == 0 ? plainBody : rawContent
        case .url(_, let originalStr):
            text = originalStr
        default:
            text = rawContent
        }

        var attributed = AttributedString(text)
        attributed.font = textMode == 0
            ? .system(size: 13.5)
            : .system(size: 12.5, design: .monospaced)
        attributed.foregroundColor = Color.primary.opacity(0.9)
        return searchHighlighted(attributed)
    }

    private var structuredAttributed: AttributedString {
        let base: AttributedString
        switch contentType {
        case .json(let pretty, let minified):
            switch jsonMode {
            case 0: base = TextIntelligence.highlightJSON(pretty)
            case 1: base = monospacedText(minified)
            default: base = monospacedText(rawContent)
            }
        case .code(let lang, let formatted):
            base = codeMode == 0
                ? TextIntelligence.highlight(code: formatted, language: lang)
                : monospacedText(rawContent)
        default:
            base = monospacedText(rawContent)
        }
        return searchHighlighted(base)
    }

    private func monospacedText(_ string: String) -> AttributedString {
        var attributed = AttributedString(string)
        attributed.font = .system(size: 12.5, design: .monospaced)
        attributed.foregroundColor = Color(red: 0.15, green: 0.15, blue: 0.2)
        return attributed
    }

    /// 在已渲染的富文本上叠加搜索高亮
    private func searchHighlighted(_ base: AttributedString) -> AttributedString {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }

        var result = base
        let plain = String(base.characters)
        var cursor = plain.startIndex

        while cursor < plain.endIndex,
              let range = plain.range(of: query, options: .caseInsensitive, range: cursor..<plain.endIndex) {
            let offset = plain.distance(from: plain.startIndex, to: range.lowerBound)
            let length = plain.distance(from: range.lowerBound, to: range.upperBound)
            if length > 0 {
                let lower = result.characters.index(result.startIndex, offsetBy: offset)
                let upper = result.characters.index(lower, offsetBy: length)
                result[lower..<upper].backgroundColor = Color.yellow.opacity(0.35)
                result[lower..<upper].foregroundColor = Color.black
            }
            cursor = range.upperBound
        }
        return result
    }

    // MARK: - 状态与辅助

    private var currentFormattedContent: String {
        switch contentType {
        case .json(let pretty, let minified):
            if jsonMode == 0 { return pretty }
            if jsonMode == 1 { return minified }
            return rawContent
        case .code(_, let formatted):
            if codeMode == 0 { return formatted }
            return rawContent
        case .url(_, let originalStr):
            return originalStr
        case .plainText:
            return rawContent
        }
    }

    private var displayedLinesCount: Int {
        currentFormattedContent.components(separatedBy: .newlines).count
    }

    private var shouldShowLineNumbers: Bool {
        switch contentType {
        case .json: return jsonMode != 1
        case .code: return true
        default: return textMode == 1
        }
    }

    private var typeIcon: String {
        switch contentType {
        case .url: return "globe"
        case .json: return "curlybraces"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .plainText: return "text.alignleft"
        }
    }

    private var typeTitle: String {
        switch contentType {
        case .url: return "网页链接"
        case .json: return "JSON 数据"
        case .code(let lang, _): return "\(lang) 代码"
        case .plainText: return "纯文本"
        }
    }
}
