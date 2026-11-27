import SwiftUI
import AppKit

/// 「最近」「收藏」的统一活动流
/// 截图与文字共用同一套行结构：媒体位 + 标题 + 摘要 + 类型/时间，按天分组。
struct LibraryFeedView: View {
    let entries: [LibraryEntry]
    let emptyTitle: String
    let emptyMessage: String
    let emptyIcon: String
    /// 收藏栏目按“收藏时间”分组，其余按内容本身的时间分组
    var groupsByFavoriteDate: Bool = false

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingNote: TextNote?
    @State private var inspectingNote: TextNote?
    @State private var noteToDelete: TextNote?
    @State private var showDeleteConfirm = false
    @State private var draft = ""
    @State private var copiedID: String?
    @State private var query = ""
    @State private var hoveredID: String?
    @ObservedObject private var webStore = WebMetadataStore.shared

    private let mediaSize = CGSize(width: 88, height: 56)
    private let hairline = Color.primary.opacity(0.07)
    private let paneBackground = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                LibrarySearchField(text: $query, prompt: "搜索截图或文字")
                    .frame(width: 230)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            if entries.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptyIcon,
                    description: Text(emptyMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleEntries.isEmpty {
                ContentUnavailableView(
                    "没有匹配的内容",
                    systemImage: "magnifyingglass",
                    description: Text("换个关键词再试试")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedEntries) { group in
                            SwiftUI.Section {
                                ForEach(group.entries) { entry in
                                    row(entry)
                                }
                            } header: {
                                LibraryDayHeader(title: group.title, count: group.entries.count)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        }
        .lensoAnimation(LensoAnimations.snappy, value: query, reduceMotion: reduceMotion)
        .sheet(item: $editingNote) { note in
            NoteEditorSheet(
                text: $draft,
                onCancel: { editingNote = nil },
                onSave: {
                    try? ScreenshotStore.shared.updateTextNote(id: note.id, content: draft)
                    editingNote = nil
                    NotificationCenter.default.post(name: .textNotesChanged, object: nil)
                    NotificationCenter.default.post(name: .libraryChanged, object: nil)
                }
            )
        }
        .sheet(item: $inspectingNote) { note in
            TextDetailInspectorSheet(
                rawContent: note.content,
                sourceApp: note.sourceApp,
                createdAt: note.createdAt,
                isSavedNote: true,
                onDismiss: { inspectingNote = nil }
            )
        }
        .alert(
            "确定删除这条便签？",
            isPresented: $showDeleteConfirm,
            presenting: noteToDelete
        ) { note in
            Button("删除", role: .destructive) {
                delete(note)
                noteToDelete = nil
            }
            Button("取消", role: .cancel) {
                noteToDelete = nil
            }
        } message: { _ in
            Text("删除后将无法恢复，此操作不可撤销。")
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func row(_ entry: LibraryEntry) -> some View {
        if let record = entry.screenshot {
            screenshotRow(entry, record: record)
        } else if let note = entry.note {
            noteRow(entry, note: note)
        }
    }

    private func screenshotRow(_ entry: LibraryEntry, record: ScreenshotRecord) -> some View {
        let isCopied = copiedID == entry.id

        return HStack(spacing: 12) {
            mediaSlot {
                if let thumbnail = entry.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: mediaSize.width, height: mediaSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("截图 · \(record.width) × \(record.height)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .monospacedDigit()
                    .lineLimit(1)

                Text(screenshotSubtitle(record))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailingMeta(isCopied: isCopied, label: "截图", date: displayDate(entry)) {
                FavoriteStarButton(isFavorite: entry.isFavorite, size: 11) {
                    toggleScreenshotFavorite(record)
                }

                Button {
                    openFloatingPreview(record)
                } label: {
                    rowIcon("eye", active: false)
                }
                .buttonStyle(LensoPressButtonStyle())
                .help("打开预览")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredID == entry.id ? Color.primary.opacity(0.04) : Color.clear)
        )
        .lensoAnimation(LensoAnimations.hover, value: hoveredID == entry.id, reduceMotion: reduceMotion)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredID = hovering ? entry.id : (hoveredID == entry.id ? nil : hoveredID)
        }
        .onTapGesture(count: 2) { openFloatingPreview(record) }
        .onTapGesture { copyScreenshot(record, entry: entry) }
        .help("单击复制 · 双击打开预览")
        .contextMenu {
            Button("复制图片") { copyScreenshot(record, entry: entry) }
            Button(entry.isFavorite ? "取消收藏" : "收藏") { toggleScreenshotFavorite(record) }
            Button("打开预览") { openFloatingPreview(record) }
        }
    }

    private func noteRow(_ entry: LibraryEntry, note: TextNote) -> some View {
        let isCopied = copiedID == entry.id
        let type = TextIntelligence.detect(note.content)
        let info = TextNoteFace.typeInfo(type)

        return HStack(spacing: 12) {
            mediaSlot {
                Image(systemName: info.icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(LensoColors.kleinBlueBright)
            }
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LensoColors.kleinBlueSoft)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(TextNoteFace.title(for: note, type: type))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .lineLimit(1)

                Text(TextNoteFace.subtitle(for: note, type: type))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailingMeta(isCopied: isCopied, label: info.label, date: displayDate(entry)) {
                FavoriteStarButton(isFavorite: entry.isFavorite, size: 11) {
                    toggleNoteFavorite(note)
                }

                Button {
                    inspectingNote = note
                } label: {
                    rowIcon("eye", active: false)
                }
                .buttonStyle(LensoPressButtonStyle())
                .help("查看全文与格式化")

                Menu {
                    Button("编辑便签") {
                        draft = note.content
                        editingNote = note
                    }
                    Button("删除便签", role: .destructive) {
                        noteToDelete = note
                        showDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredID == entry.id ? Color.primary.opacity(0.04) : Color.clear)
        )
        .lensoAnimation(LensoAnimations.hover, value: hoveredID == entry.id, reduceMotion: reduceMotion)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredID = hovering ? entry.id : (hoveredID == entry.id ? nil : hoveredID)
        }
        .onAppear {
            if case .url(_, let originalStr) = type {
                webStore.fetchTitleIfNeeded(for: originalStr)
            }
        }
        .onTapGesture(count: 2) { inspectingNote = note }
        .onTapGesture { copy(note, entry: entry) }
        .help("单击复制 · 双击查看全文")
        .contextMenu {
            Button("复制文本") { copy(note, entry: entry) }
            Button(entry.isFavorite ? "取消收藏" : "收藏") { toggleNoteFavorite(note) }
            Divider()
            Button("编辑便签") {
                draft = note.content
                editingNote = note
            }
            Button("删除便签", role: .destructive) {
                noteToDelete = note
                showDeleteConfirm = true
            }
        }
    }

    // MARK: - 行组件

    private func mediaSlot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            content()
        }
        .frame(width: mediaSize.width, height: mediaSize.height)
    }

    private func trailingMeta<Actions: View>(
        isCopied: Bool,
        label: String,
        date: Date,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 7) {
            if isCopied {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .lensoSymbolReplace()
                    Text("已复制")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(red: 0.11, green: 0.55, blue: 0.33))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(red: 0.11, green: 0.55, blue: 0.33).opacity(0.10)))
                .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            } else {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.42))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                    .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }

            Text(Self.timeOnlyFormatter.string(from: date))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.32))

            actions()
        }
        .lensoAnimation(LensoAnimations.snappy, value: isCopied, reduceMotion: reduceMotion)
    }

    private func rowIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 10.5))
            .foregroundStyle(active ? LensoColors.kleinBlueBright : Color.primary.opacity(0.38))
            .frame(width: 22, height: 22)
    }

    // MARK: - 分组

    private struct FeedDayGroup: Identifiable {
        let id: Date
        let title: String
        let entries: [LibraryEntry]
    }

    private var visibleEntries: [LibraryEntry] {
        TextNoteFace.matches(entries, query: query)
    }

    private var groupedEntries: [FeedDayGroup] {
        let calendar = Calendar.current
        var buckets: [Date: [LibraryEntry]] = [:]
        for entry in visibleEntries {
            let day = calendar.startOfDay(for: displayDate(entry))
            buckets[day, default: []].append(entry)
        }
        return buckets.keys.sorted(by: >).map { day in
            FeedDayGroup(id: day, title: LibraryDayLabel.title(for: day), entries: buckets[day] ?? [])
        }
    }

    private static let timeOnlyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    private func displayDate(_ entry: LibraryEntry) -> Date {
        groupsByFavoriteDate ? (entry.favoriteDate ?? entry.date) : entry.date
    }

    // MARK: - 文案

    private func screenshotSubtitle(_ record: ScreenshotRecord) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(record.fileSize), countStyle: .file)
        let ext = (record.filename as NSString).pathExtension.uppercased()
        let meta = ext.isEmpty ? size : "\(size) · \(ext)"
        return "\(record.sourceApp ?? "截图") · \(meta)"
    }

    // MARK: - 交互操作

    private func copyScreenshot(_ record: ScreenshotRecord, entry: LibraryEntry) {
        if let cgImage = ScreenshotStore.shared.loadImage(record) {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let tiff = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)).tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
            copiedID = entry.id
            SaveToastController.shared.show(title: "已复制图片", subtitle: "", thumbnail: cgImage)
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run { if copiedID == entry.id { copiedID = nil } }
            }
        }
    }

    private func copy(_ note: TextNote, entry: LibraryEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(note.content, forType: .string)
        copiedID = entry.id
        SaveToastController.shared.show(title: "已复制便签文本", subtitle: "", thumbnail: nil)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run { if copiedID == entry.id { copiedID = nil } }
        }
    }

    private func openFloatingPreview(_ record: ScreenshotRecord) {
        let store = ScreenshotStore.shared
        guard let cgImage = store.loadImage(record) else { return }
        CaptureCoordinator.shared.pin(image: cgImage, isPreview: true)
    }

    private func toggleScreenshotFavorite(_ record: ScreenshotRecord) {
        try? ScreenshotStore.shared.setScreenshotFavorite(!record.isFavorite, id: record.id)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }

    private func toggleNoteFavorite(_ note: TextNote) {
        try? ScreenshotStore.shared.setTextNoteFavorite(!note.isFavorite, id: note.id)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }

    private func delete(_ note: TextNote) {
        try? ScreenshotStore.shared.deleteTextNote(id: note.id)
        NotificationCenter.default.post(name: .textNotesChanged, object: nil)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }
}
