import SwiftUI
import AppKit

/// Spotlight 风格全局搜索与最近剪贴板聚合面板
/// 唤出搜索直接按时间倒序展示最新复制的文字与图片，支持分类过滤、实时检索与平滑滚动查看
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
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            // 顶部搜索胶囊栏
            searchHeader

            // 分类筛选与数量统计栏
            filterBar

            // 滚动查看内容流（图文聚合，时间倒序）
            scrollContent
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.985, green: 0.988, blue: 0.995))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
        .shadow(color: Color.black.opacity(0.22), radius: 32, y: 14)
        .onAppear {
            focused = true
            reloadFeed()
        }
        .onChange(of: searchText) { _ in reloadFeed() }
        .onChange(of: selectedCategory) { _ in reloadFeed() }
        .onExitCommand { onDismiss() }
        .lensoColorScheme()
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
                    // 回车直接复制第一项
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
        .frame(height: 52)
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

            Text("共 \(filteredItems.count) 条记录 · 时间倒序")
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

    // MARK: - 滚动流

    private var scrollContent: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(LensoColors.kleinBlueBright.opacity(0.45))
                    Text(searchText.isEmpty ? "还没有最近复制记录" : "未找到匹配的内容")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "复制任何文字或截取图片将自动在此归集显示" : "请尝试更换关键词")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            cardView(for: item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - 单元卡片视图

    @ViewBuilder
    private func cardView(for item: FeedItem) -> some View {
        let isCopied = copiedID == item.id

        HStack(spacing: 12) {
            // 左侧：图片缩略图 或 文字图标
            switch item.kind {
            case .image(let cgImage, _):
                if let cgImage {
                    Image(decorative: cgImage, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                        .frame(width: 72, height: 50)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }

            case .text:
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LensoColors.kleinBlueSoft)
                        .frame(width: 44, height: 44)
                    Image(systemName: "text.quote")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                }
            }

            // 中间：主内容与副标题
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let app = item.sourceApp, !app.isEmpty {
                        Text(app)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.05)))
                            .foregroundStyle(.secondary)
                    }

                    Text(relativeTime(item.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.9))
                    .lineLimit(2)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // 右侧操作栏：复制反馈 / 查看预览 / 复制按钮
            HStack(spacing: 6) {
                if isCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                        Text("已复制")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                } else {
                    // 若是图片，提供查看大图按钮
                    if case .image(let cgImage, _) = item.kind, let cgImage {
                        Button {
                            openFloatingPreview(cgImage)
                        } label: {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.75))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.black.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                        .help("打开无边框贴图预览")
                    }

                    // 复制按钮
                    Button {
                        copyItem(item)
                    } label: {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(LensoColors.kleinBlueSoft))
                    }
                    .buttonStyle(.plain)
                    .help("重新复制到剪贴板")

                    // 删除单个记录
                    Button {
                        deleteSingleItem(item)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.red.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("彻底永久删除此条记录")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.02), radius: 3, y: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            copyItem(item)
        }
    }

    // MARK: - 数据加载与过滤

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

        // 1. 读取剪贴板历史（图文混合）
        if let clipItems = try? store.listClipboard(limit: 120) {
            for clip in clipItems {
                switch clip.kind {
                case .text:
                    if let text = clip.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

        // 2. 读取截图记录（若不在剪贴板历史中则融合进来，保证截图也能搜到）
        if let records = try? store.list() {
            for record in records {
                let thumb = store.loadThumbnail(record) ?? store.loadImage(record)
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

        // 3. 读取文字收纳便签
        if let notes = try? store.listTextNotes() {
            for note in notes {
                feed.append(FeedItem(
                    id: note.id,
                    kind: .text(content: note.content),
                    title: note.content.replacingOccurrences(of: "\n", with: " "),
                    subtitle: "收纳便签 · \(note.content.count) 个字符",
                    sourceApp: note.sourceApp ?? "收纳",
                    createdAt: note.createdAt,
                    rawText: note.content,
                    thumbnail: nil,
                    clipboardID: nil
                ))
            }
        }

        // 去重并按创建时间绝对倒序（最新复制/截图排在最顶部）
        var seenIDs = Set<UUID>()
        var unique: [FeedItem] = []
        for f in feed {
            if !seenIDs.contains(f.id) {
                seenIDs.insert(f.id)
                unique.append(f)
            }
        }
        unique.sort { $0.createdAt > $1.createdAt }
        items = unique
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

    private func deleteSingleItem(_ item: FeedItem) {
        let store = ScreenshotStore.shared
        if let clipID = item.clipboardID {
            try? store.deleteClipboardItem(id: clipID)
        } else if case .image(_, let recID) = item.kind, let recID {
            if let record = (try? store.list())?.first(where: { $0.id == recID }) {
                try? store.delete(record)
            }
        } else if case .text = item.kind {
            try? store.deleteTextNote(id: item.id)
        }
        reloadFeed()
    }

    private func clearHistory() {
        try? ScreenshotStore.shared.clearClipboardHistory()
        reloadFeed()
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(max(1, Int(interval / 60))) 分钟前" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
