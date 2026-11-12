import SwiftUI
import AppKit

/// 文本详情全量查看与智能格式化高亮弹窗
/// 支持长文本无截断阅读、JSON 美化与压缩、C/C++ 代码语法高亮与自动对齐、网页富卡片预览及一键打开
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

    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            headerBar

            Divider().opacity(0.6)

            // 如果是网址，呈现专属精美网页预览卡片
            if case .url(let url, let originalStr) = contentType {
                urlBannerCard(url: url, originalString: originalStr)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }

            // 操作控制与模式切换工具栏
            formatToolbar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

            Divider().opacity(0.5)

            // 核心正文查看区（带行号、语法高亮与全选复制）
            mainContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.6)

            // 底部状态与操作栏
            footerBar
        }
        .frame(minWidth: 700, idealWidth: 780, maxWidth: 900, minHeight: 520, idealHeight: 580)
        .background(Color(red: 0.985, green: 0.988, blue: 0.995))
        .onAppear {
            contentType = TextIntelligence.detect(rawContent)
            if case .url(_, let originalStr) = contentType {
                webStore.fetchTitleIfNeeded(for: originalStr)
            }
        }
        .lensoColorScheme()
    }

    // MARK: - 顶部导航栏

    private var headerBar: some View {
        HStack(spacing: 10) {
            // 类型标志
            HStack(spacing: 6) {
                Image(systemName: typeIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LensoColors.kleinBlueBright)
                Text(typeTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.9))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(LensoColors.kleinBlueSoft))

            if let app = sourceApp, !app.isEmpty {
                Text(app)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.black.opacity(0.04)))
            }

            Spacer()

            // 精准时间戳
            Text(DateFormatter.lensoFullDateTime.string(from: createdAt))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            // 关闭按钮
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help("关闭 (Esc)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - 专属网页卡片 Banner (当识别到是网址时呈现)

    private func urlBannerCard(url: URL, originalString: String) -> some View {
        let webTitle = webStore.title(for: originalString) ?? url.host ?? originalString

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [LensoColors.kleinBlueBright, LensoColors.kleinBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "globe")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(webTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .lineLimit(1)
                    if let host = url.host {
                        Text(host)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(LensoColors.kleinBlueSoft))
                    }
                }

                Text(originalString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 在默认浏览器中打开
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 4) {
                    Text("打开网页")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(LensoColors.kleinBlueBright))
                .shadow(color: LensoColors.kleinBlueBright.opacity(0.25), radius: 4, y: 1.5)
            }
            .buttonStyle(.plain)
            .help("在系统默认浏览器中打开此网页")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        )
    }

    // MARK: - 模式与格式化工具栏

    private var formatToolbar: some View {
        HStack(spacing: 12) {
            // 模式切换
            switch contentType {
            case .json:
                Picker("", selection: $jsonMode) {
                    Text("美化格式化 (2格缩进)").tag(0)
                    Text("紧凑单行").tag(1)
                    Text("原始纯文本").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 270)

            case .code:
                Picker("", selection: $codeMode) {
                    Text("语法高亮美化").tag(0)
                    Text("原始代码").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

            case .url, .plainText:
                Picker("", selection: $textMode) {
                    Text("自然排版").tag(0)
                    Text("等宽代码模式").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            Spacer()

            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("在正文中搜索…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 130)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.04)))
        }
    }

    // MARK: - 正文内容视图 (支持代码高亮、长文本滚动阅读与行号)

    private var mainContentView: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 14) {
                // 行号栏 (在代码模式或JSON模式下呈现)
                if shouldShowLineNumbers {
                    VStack(alignment: .trailing, spacing: 4.5) {
                        ForEach(1...max(1, displayedLinesCount), id: \.self) { lineNum in
                            Text("\(lineNum)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Color.secondary.opacity(0.45))
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.leading, 14)

                    Divider().opacity(0.3)
                }

                // 核心文字正文
                VStack(alignment: .leading, spacing: 0) {
                    renderedText
                        .textSelection(.enabled)
                        .padding(.vertical, 14)
                        .padding(.trailing, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.white)
    }

    // MARK: - 动态文本渲染

    @ViewBuilder
    private var renderedText: some View {
        switch contentType {
        case .json(let pretty, let minified):
            if jsonMode == 0 {
                Text(TextIntelligence.highlightJSON(pretty))
                    .lineSpacing(4)
            } else if jsonMode == 1 {
                Text(minified)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.2))
                    .lineSpacing(4)
            } else {
                Text(rawContent)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(4)
            }

        case .code(let lang, let formatted):
            if codeMode == 0 {
                Text(TextIntelligence.highlight(code: formatted, language: lang))
                    .lineSpacing(4)
            } else {
                Text(rawContent)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.2))
                    .lineSpacing(4)
            }

        case .url(_, let originalStr):
            Text(originalStr)
                .font(.system(size: textMode == 0 ? 14 : 12.5, design: textMode == 0 ? .default : .monospaced))
                .foregroundStyle(Color.primary.opacity(0.9))
                .lineSpacing(4)

        case .plainText:
            Text(rawContent)
                .font(.system(size: textMode == 0 ? 13.5 : 12.5, design: textMode == 0 ? .default : .monospaced))
                .foregroundStyle(Color.primary.opacity(0.9))
                .lineSpacing(textMode == 0 ? 5 : 4)
        }
    }

    // MARK: - 底部状态与操作栏

    private var footerBar: some View {
        HStack(spacing: 16) {
            // 统计信息
            HStack(spacing: 12) {
                Text("共 \(rawContent.count) 个字符")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.secondary.opacity(0.5))

                Text("\(displayedLinesCount) 行")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 存为便签
            Button {
                _ = try? ScreenshotStore.shared.createTextNote(content: currentFormattedContent, sourceApp: sourceApp ?? "查看器")
                SaveToastController.shared.show(title: "已保存为收纳便签", subtitle: "", thumbnail: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark")
                    Text("存为便签")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.8))
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(Color.black.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .help("保存至文字收纳库")

            // 复制按钮
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
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                    Text(copied ? "已复制" : "复制当前文本")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(copied ? Color.green : LensoColors.kleinBlueBright))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.white)
    }

    // MARK: - 辅助计算

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
