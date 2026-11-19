import SwiftUI
import AppKit

/// 文字收纳 — 左侧列表定位，右侧直接预览全文
/// 列表按天分组，窄窗口自动折回单栏（点击直接打开详情）。
struct TextNotesView: View {
    @State private var notes: [TextNote] = []
    @State private var editing: TextNote?
    @State private var inspecting: TextNote?
    @State private var selectedNoteID: UUID?
    @State private var query = ""
    @State private var hoveredNoteID: UUID?
    @State private var draft = ""
    @State private var copiedID: UUID?
    @ObservedObject private var webStore = WebMetadataStore.shared

    private let hairline = Color.black.opacity(0.06)

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                header
                if notes.isEmpty {
                    emptyState
                } else {
                    splitContent(showsPreview: proxy.size.width >= 720)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editing) { note in
            NoteEditorSheet(
                text: $draft,
                onCancel: { editing = nil },
                onSave: {
                    try? ScreenshotStore.shared.updateTextNote(id: note.id, content: draft)
                    editing = nil
                    reload()
                    NotificationCenter.default.post(name: .textNotesChanged, object: nil)
                    NotificationCenter.default.post(name: .libraryChanged, object: nil)
                }
            )
        }
        .sheet(item: $inspecting) { note in
            TextDetailInspectorSheet(
                rawContent: note.content,
                sourceApp: note.sourceApp,
                createdAt: note.createdAt,
                onDismiss: { inspecting = nil }
            )
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .textNotesChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryChanged)) { _ in reload() }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Text("文字收纳")
                    .font(.system(size: 15, weight: .bold))
                Text("\(visibleNotes.count) 条")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            LibrarySearchField(text: $query, prompt: "搜索便签内容")
                .frame(width: 220)
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有文字收纳卡片",
            systemImage: "text.alignleft",
            description: Text("复制的文字或截图 OCR 提取的内容会自动在此生成条目")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 分栏容器

    private func splitContent(showsPreview: Bool) -> some View {
        HStack(spacing: 0) {
            listPane(opensOnTap: !showsPreview)
                .frame(width: showsPreview ? 300 : nil)

            if showsPreview {
                Rectangle().fill(hairline).frame(width: 0.5)
                previewPane
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.8)
        )
    }

    // MARK: - 左侧列表

    private func listPane(opensOnTap: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedNotes) { group in
                    SwiftUI.Section {
                        ForEach(group.notes) { note in
                            noteRow(note, opensOnTap: opensOnTap)
                        }
                    } header: {
                        LibraryDayHeader(title: group.title, count: group.notes.count)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(red: 0.984, green: 0.988, blue: 0.996))
    }

    private func noteRow(_ note: TextNote, opensOnTap: Bool) -> some View {
        let type = TextIntelligence.detect(note.content)
        let info = TextNoteFace.typeInfo(type)
        let selected = selectedNote?.id == note.id
        let hovered = hoveredNoteID == note.id
        let title = TextNoteFace.title(for: note, type: type)
        let subtitle = TextNoteFace.subtitle(for: note, type: type)

        return HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.white : LensoColors.kleinBlueSoft)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: info.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineLimit(1)

                Text(rowMeta(note))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.32))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? LensoColors.kleinBlueSoft : (hovered ? Color.black.opacity(0.03) : Color.clear))
        )
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LensoColors.kleinBlueBright)
                    .frame(width: 2, height: 20)
                    .padding(.leading, 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredNoteID = hovering ? note.id : (hoveredNoteID == note.id ? nil : hoveredNoteID)
        }
        .onTapGesture(count: 2) {
            selectedNoteID = note.id
            inspecting = note
        }
        .onTapGesture {
            if opensOnTap {
                inspecting = note
            } else {
                selectedNoteID = note.id
            }
        }
        .help(opensOnTap ? "打开全文" : "单击预览 · 双击打开完整查看器")
        .padding(.horizontal, 6)
        .contextMenu {
            Button("复制文本") { copy(note) }
            Button(note.isFavorite ? "取消收藏" : "收藏") { toggleFavorite(note) }
            Divider()
            Button("编辑内容") {
                draft = note.content
                editing = note
            }
            Button("删除", role: .destructive) { delete(note) }
        }
    }

    // MARK: - 右侧预览

    @ViewBuilder
    private var previewPane: some View {
        if let note = selectedNote {
            let type = TextIntelligence.detect(note.content)

            VStack(spacing: 0) {
                previewHeader(note, type: type)
                Rectangle().fill(hairline).frame(height: 0.5)
                previewContent(note, type: type)
                Rectangle().fill(hairline).frame(height: 0.5)
                previewFooter(note)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        } else {
            Color.white
        }
    }

    private func previewHeader(_ note: TextNote, type: TextIntelligence.ContentType) -> some View {
        let info = TextNoteFace.typeInfo(type)

        return HStack(spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: info.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(info.label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(LensoColors.kleinBlueBright)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(LensoColors.kleinBlueSoft))

            if let source = note.sourceApp, !source.isEmpty {
                Text(source)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.black.opacity(0.045)))
            }

            Spacer()

            Text(note.updatedAt.lensoRelativeDayTime)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.35))

            Button {
                toggleFavorite(note)
            } label: {
                Image(systemName: note.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(note.isFavorite ? Color.yellow : Color.primary.opacity(0.4))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(note.isFavorite ? "取消收藏" : "收藏")

            Button {
                inspecting = note
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LensoColors.kleinBlueBright)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(LensoColors.kleinBlueSoft))
            }
            .buttonStyle(.plain)
            .help("打开完整查看器")

            Menu {
                Button("编辑内容") {
                    draft = note.content
                    editing = note
                }
                Button("删除", role: .destructive) { delete(note) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .frame(width: 20, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func previewContent(_ note: TextNote, type: TextIntelligence.ContentType) -> some View {
        ScrollView(.vertical) {
            switch type {
            case .json(let pretty, _):
                Text(pretty)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(red: 0.15, green: 0.18, blue: 0.24))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)

            case .code(_, let formatted):
                Text(formatted)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(red: 0.15, green: 0.18, blue: 0.24))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)

            case .url(let url, let originalStr):
                VStack(alignment: .leading, spacing: 10) {
                    Text(webStore.title(for: originalStr) ?? url.host ?? originalStr)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .onAppear { webStore.fetchTitleIfNeeded(for: originalStr) }

                    Text(originalStr)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 4) {
                            Text("打开网页")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(LensoColors.kleinBlueBright))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)

            case .plainText:
                let parts = noteParts(note)
                VStack(alignment: .leading, spacing: 0) {
                    if let title = parts.title {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.primary.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 10)
                    }

                    Text(parts.body)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.88))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
        }
    }

    private func previewFooter(_ note: TextNote) -> some View {
        let isCopied = copiedID == note.id
        let lines = note.content.components(separatedBy: .newlines).count

        return HStack(spacing: 8) {
            Text("\(note.content.count) 字符 · \(lines) 行")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.38))

            Spacer()

            Button {
                copy(note)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc.fill")
                    Text(isCopied ? "已复制" : "复制全部")
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5.5)
                .background(
                    Capsule().fill(
                        isCopied
                            ? Color(red: 0.11, green: 0.55, blue: 0.33)
                            : LensoColors.kleinBlueBright
                    )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    // MARK: - 按天分组（与其他栏目一致）

    private struct NoteDayGroup: Identifiable {
        let id: Date
        let title: String
        let notes: [TextNote]
    }

    private var visibleNotes: [TextNote] {
        TextNoteFace.matches(notes, query: query)
    }

    private var groupedNotes: [NoteDayGroup] {
        let calendar = Calendar.current
        var buckets: [Date: [TextNote]] = [:]
        for note in visibleNotes {
            let day = calendar.startOfDay(for: note.updatedAt)
            buckets[day, default: []].append(note)
        }
        return buckets.keys.sorted(by: >).map { day in
            NoteDayGroup(id: day, title: LibraryDayLabel.title(for: day), notes: buckets[day] ?? [])
        }
    }

    // MARK: - 文案提取

    private var selectedNote: TextNote? {
        if let id = selectedNoteID, let note = visibleNotes.first(where: { $0.id == id }) {
            return note
        }
        return visibleNotes.first
    }

    private func rowMeta(_ note: TextNote) -> String {
        let source = (note.sourceApp?.isEmpty == false) ? note.sourceApp! : "LENSO"
        return "\(source) · \(note.updatedAt.lensoRelativeDayTime)"
    }

    /// 纯文本：首行提为标题，剩余作为正文
    private func noteParts(_ note: TextNote) -> (title: String?, body: String) {
        let lines = note.content.components(separatedBy: .newlines)
        guard lines.count > 1 else { return (nil, note.content) }

        let first = lines[0].trimmingCharacters(in: .whitespaces)
        guard first.count >= 4, first.count <= 64 else { return (nil, note.content) }

        let rest = lines.dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return (nil, note.content) }

        return (first, rest)
    }

    // MARK: - 操作

    private func reload() {
        notes = (try? ScreenshotStore.shared.listTextNotes()) ?? []
        if selectedNoteID == nil || !notes.contains(where: { $0.id == selectedNoteID }) {
            selectedNoteID = notes.first?.id
        }
    }

    private func copy(_ note: TextNote) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(note.content, forType: .string)
        copiedID = note.id
        SaveToastController.shared.show(title: "已复制便签文本", subtitle: "", thumbnail: nil)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                if copiedID == note.id { copiedID = nil }
            }
        }
    }

    private func toggleFavorite(_ note: TextNote) {
        try? ScreenshotStore.shared.setTextNoteFavorite(!note.isFavorite, id: note.id)
        reload()
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }

    private func delete(_ note: TextNote) {
        try? ScreenshotStore.shared.deleteTextNote(id: note.id)
        reload()
        NotificationCenter.default.post(name: .textNotesChanged, object: nil)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }
}
