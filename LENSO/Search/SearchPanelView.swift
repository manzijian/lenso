import SwiftUI
import AppKit

/// 通用中文完整日期时间格式化工具：统一输出「年月日时分秒」
extension DateFormatter {
    static let lensoFullDateTime: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy年MM月dd日 HH:mm:ss"
        df.locale = Locale(identifier: "zh_CN")
        return df
    }()
}

/// Spotlight 风格全局搜索与最近剪贴板聚合画廊
/// 采用方块形照片网格铺满排版（LazyVGrid），支持窗口自由拖拽移动，
/// 整合展示截图与复制文字，并以「年月日时分秒」精准呈现时间。
struct SearchPanelView: View {
    var onDismiss: () -> Void = {}

    enum FilterCategory: String, CaseIterable, Identifiable {
        case all = "全部"
        case text = "文字"
        case images = "图片"
        var id: String { rawValue }
    }

    enum FeedKind {
        case text(content: String)
        case image(cgImage: CGImage?, recordID: UUID?)
    }

    struct FeedItem: Identifiable {
        let id: UUID
        let kind: FeedKind
        let title: String
        let subtitle: String
        let sourceApp: String?
        let createdAt: Date
        let rawText: String?
        let thumbnail: CGImage?
        let clipboardID: UUID?
    }

    @State private var searchText = ""
    @State private var selectedCategory: FilterCategory = .all
    @State private var items: [FeedItem] = []
    @State private var copiedID: UUID?
    @State private var inspectingItem: FeedItem?
    @ObservedObject private var webStore = WebMetadataStore.shared
    @FocusState private var focused: Bool

    // 方块形网格布局：自适应列宽（185~230pt），如同相册照片墙铺满整个界面
    private let gridColumns = [
        GridItem(.adaptive(minimum: 185, maximum: 230), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 10) {
            // 顶部拖拽手柄指示条（按住可拖动窗口）
            topDragBar

            // 顶部搜索胶囊栏
            searchHeader

            // 分类筛选与数量统计栏
            filterBar

            // 照片级方块铺满网格流（图文聚合，时间倒序）
            scrollContent
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.985, green: 0.988, blue: 0.995))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    )
                // 背景区域可全局直接拖拽窗口
                WindowDragHandleView()
            }
        }
        .shadow(color: Color.black.opacity(0.22), radius: 32, y: 14)
        .onAppear {
            focused = true
            reloadFeed()
        }
        .onChange(of: searchText) { _ in reloadFeed() }
        .onChange(of: selectedCategory) { _ in reloadFeed() }
        .onReceive(NotificationCenter.default.publisher(for: .searchPanelShouldReload)) { _ in reloadFeed() }
        .onReceive(NotificationCenter.default.publisher(for: .textNotesChanged)) { _ in reloadFeed() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryChanged)) { _ in reloadFeed() }
        .onReceive(NotificationCenter.default.publisher(for: .screenshotSaved)) { _ in reloadFeed() }
        .onExitCommand {
            if inspectingItem != nil {
                withAnimation(.easeInOut(duration: 0.2)) { inspectingItem = nil }
            } else {
                onDismiss()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchPanelEscapePressed)) { _ in
            if inspectingItem != nil {
                withAnimation(.easeInOut(duration: 0.2)) { inspectingItem = nil }
            } else {
                onDismiss()
            }
        }
        .overlay {
            SearchPanelInspectionOverlay(
                item: $inspectingItem,
                onCopyItem: { copyItem($0) },
                onPinImage: { openFloatingPreview($0) }
            )
        }
        .lensoColorScheme()
    }

    // MARK: - 顶部拖拽把手

    private var topDragBar: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.black.opacity(0.18))
                .frame(width: 44, height: 4.5)
            Spacer()
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
        .background(WindowDragHandleView())
        .help("按住可拖拽移动此窗口")
    }

    // MARK: - 顶部搜索胶囊

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LensoColors.kleinBlueBright)

            TextField("搜索最近复制的文字、截图或关键词…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit {
                    if let first = filteredItems.first {
                        copyItem(first)
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // 拖拽窗口移动图标提示
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .help("拖拽窗口任意空白区可移动位置")

            // 关闭按钮
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help("关闭搜索 (Esc)")
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(focused ? LensoColors.kleinBlueBright.opacity(0.6) : Color.black.opacity(0.08), lineWidth: 1.5)
                )
                .shadow(color: focused ? LensoColors.kleinBlueBright.opacity(0.12) : Color.black.opacity(0.03), radius: 8, y: 2)
        )
    }

    // MARK: - 分类切换与统计

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(FilterCategory.allCases) { cat in
                Button {
                    selectedCategory = cat
                } label: {
                    HStack(spacing: 5) {
                        Text(cat.rawValue)
                            .font(.system(size: 12, weight: selectedCategory == cat ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(selectedCategory == cat ? LensoColors.kleinBlueBright : Color.black.opacity(0.04))
                    )
                    .foregroundStyle(selectedCategory == cat ? Color.white : Color.primary.opacity(0.75))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("共 \(filteredItems.count) 项 · 按时间倒序")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // 清空剪贴板历史
            Button {
                clearHistory()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("清空剪贴板历史记录")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 方块形铺满内容流（类似照片相册卡片）

    private var scrollContent: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "photo.stack" : "magnifyingglass")
                        .font(.system(size: 38))
                        .foregroundStyle(LensoColors.kleinBlueBright.opacity(0.45))
                    Text(searchText.isEmpty ? "暂无最近复制记录" : "未找到匹配的内容")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "截取图片或复制任何文字，将自动在此形成方块卡片归集" : "请尝试更换关键词")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 14) {
                        ForEach(filteredItems) { item in
                            tileView(for: item)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - 方块卡片分发

    @ViewBuilder
    private func tileView(for item: FeedItem) -> some View {
        switch item.kind {
        case .image(let cgImage, _):
            SearchPanelScreenshotTile(
                item: item,
                cgImage: cgImage,
                isCopied: copiedID == item.id,
                onCopy: { copyItem(item) },
                onInspect: { inspectingItem = item }
            )
        case .text(let content):
            SearchPanelTextTile(
                item: item,
                content: content,
                isCopied: copiedID == item.id,
                onCopy: { copyItem(item) },
                onInspect: { inspectingItem = item },
                webStore: webStore
            )
        }
    }

    // MARK: - 过滤逻辑

    private var filteredItems: [FeedItem] {
        items.filter { item in
            // 分类过滤
            switch selectedCategory {
            case .all: break
            case .text:
                if case .image = item.kind { return false }
            case .images:
                if case .text = item.kind { return false }
            }

            // 关键词过滤
            let query = searchText.trimmingCharacters(in: .whitespaces)
            if query.isEmpty { return true }
            if item.title.localizedCaseInsensitiveContains(query) { return true }
            if item.subtitle.localizedCaseInsensitiveContains(query) { return true }
            if let raw = item.rawText, raw.localizedCaseInsensitiveContains(query) { return true }
            if let app = item.sourceApp, app.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
    }

    private func reloadFeed() {
        let store = ScreenshotStore.shared
        var feed: [FeedItem] = []
        var seenTexts = Set<String>()
        var seenImageHashes = Set<String>()

        // 1. 读取剪贴板历史（图文混合，最准确的复制时间流）
        if let clipItems = try? store.listClipboard(limit: 120) {
            for clip in clipItems {
                switch clip.kind {
                case .text:
                    if let text = clip.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // 文本内容去重：只保留最新的复制时间点，避免重复卡片
                        if seenTexts.contains(text) { continue }
                        seenTexts.insert(text)

                        feed.append(FeedItem(
                            id: clip.id,
                            kind: .text(content: text),
                            title: text.replacingOccurrences(of: "\n", with: " "),
                            subtitle: "\(text.count) 个字符",
                            sourceApp: clip.sourceApp,
                            createdAt: clip.createdAt,
                            rawText: text,
                            thumbnail: nil,
                            clipboardID: clip.id
                        ))
                    }
                case .image:
                    let cgImage = store.loadClipboardImage(clip)
                    // 图片特征哈希去重：相同的图片只保留最新复制的那张，节省空间
                    if let cgImage {
                        let hash = ScreenshotStore.computeImageHash(cgImage)
                        if seenImageHashes.contains(hash) { continue }
                        seenImageHashes.insert(hash)
                    }

                    feed.append(FeedItem(
                        id: clip.id,
                        kind: .image(cgImage: cgImage, recordID: nil),
                        title: "复制的图片",
                        subtitle: cgImage != nil ? "\(cgImage!.width) × \(cgImage!.height)" : "图片",
                        sourceApp: clip.sourceApp ?? "剪贴板",
                        createdAt: clip.createdAt,
                        rawText: nil,
                        thumbnail: cgImage,
                        clipboardID: clip.id
                    ))
                }
            }
        }

        // 2. 读取文字收纳便签（若该文本未在最近剪贴板中出现，则收录并以 updatedAt 时间排序）
        if let notes = try? store.listTextNotes() {
            for note in notes {
                if seenTexts.contains(note.content) { continue }
                seenTexts.insert(note.content)

                feed.append(FeedItem(
                    id: note.id,
                    kind: .text(content: note.content),
                    title: note.content.replacingOccurrences(of: "\n", with: " "),
                    subtitle: "收纳便签 · \(note.content.count) 个字符",
                    sourceApp: note.sourceApp ?? "收纳",
                    createdAt: note.updatedAt,
                    rawText: note.content,
                    thumbnail: nil,
                    clipboardID: nil
                ))
            }
        }

        // 3. 读取本地截图记录（若为历史截图且未在剪贴板中展示，融合进来）
        if let records = try? store.list() {
            for record in records {
                let thumb = store.loadThumbnail(record) ?? store.loadImage(record)
                if let thumb {
                    let hash = ScreenshotStore.computeImageHash(thumb)
                    if seenImageHashes.contains(hash) { continue }
                    seenImageHashes.insert(hash)
                }

                feed.append(FeedItem(
                    id: record.id,
                    kind: .image(cgImage: store.loadImage(record), recordID: record.id),
                    title: record.filename,
                    subtitle: "\(record.width) × \(record.height) · \(byteString(record.fileSize))",
                    sourceApp: "截图",
                    createdAt: record.capturedAt,
                    rawText: nil,
                    thumbnail: thumb,
                    clipboardID: nil
                ))
            }
        }

        // 严格按时间绝对倒序（最新复制/截图排在第 1 个，即左上角最顶端）
        feed.sort { $0.createdAt > $1.createdAt }
        items = feed
    }

    // MARK: - 交互操作

    private func copyItem(_ item: FeedItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text(let content):
            pasteboard.setString(content, forType: .string)
            SaveToastController.shared.show(title: "已复制文本", subtitle: "到剪贴板", thumbnail: nil)

        case .image(let cgImage, _):
            if let cgImage {
                if let tiff = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)).tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
                SaveToastController.shared.show(title: "已复制图片", subtitle: "到剪贴板", thumbnail: cgImage)
            }
        }

        copiedID = item.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                if copiedID == item.id { copiedID = nil }
            }
        }
    }

    private func openFloatingPreview(_ cgImage: CGImage) {
        CaptureCoordinator.shared.pin(image: cgImage, isPreview: true)
        onDismiss()
    }

    private func clearHistory() {
        try? ScreenshotStore.shared.clearClipboardHistory()
        reloadFeed()
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
