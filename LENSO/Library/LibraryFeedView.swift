import SwiftUI
import AppKit

/// 「最近」「收藏」的时间倒序卡片网格画廊
struct LibraryFeedView: View {
    let entries: [LibraryEntry]
    let emptyTitle: String
    let emptyMessage: String
    let emptyIcon: String

    @Environment(\.openWindow) private var openWindow
    @State private var editingNote: TextNote?
    @State private var inspectingNote: TextNote?
    @State private var draft = ""
    @State private var copiedID: String?
    @ObservedObject private var webStore = WebMetadataStore.shared

    private let gridColumns = [
        GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14)
    ]

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptyIcon,
                    description: Text(emptyMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 14) {
                        ForEach(entries) { entry in
                            if let record = entry.screenshot {
                                screenshotCard(entry, record: record)
                            } else if let note = entry.note {
                                noteCard(entry, note: note)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
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
                onDismiss: { inspectingNote = nil }
            )
        }
    }

    // MARK: - 截图卡片

    private func screenshotCard(_ entry: LibraryEntry, record: ScreenshotRecord) -> some View {
        let isCopied = copiedID == entry.id

        return ZStack(alignment: .bottom) {
            // 背景与图片主体
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.93, green: 0.94, blue: 0.96))

                if let thumbnail = entry.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 185)
                        .clipped()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 185)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // 顶部：来源/分辨率胶囊 + 收藏星标 + 预览
            VStack {
                HStack(spacing: 6) {
                    Text("\(record.width)×\(record.height)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.black.opacity(0.6)))

                    Spacer()

                    FavoriteStarButton(isFavorite: entry.isFavorite) {
                        toggleScreenshotFavorite(record)
                    }

                    Button {
                        openFloatingPreview(record)
                    } label: {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .help("打开预览")
                }
                .padding(8)
                Spacer()
            }

            // 底部暗色渐变层 + 年月日时分秒时间
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                HStack {
                    Text(timeText(entry.date))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .padding(.top, 28)
                .background(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // 复制反馈覆盖层
            if isCopied {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.green)
                        Text("已复制")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                }
                .transition(.opacity)
            }
        }
        .frame(height: 185)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            copyScreenshot(record, entry: entry)
        }
    }

    // MARK: - 文字便签卡片

    private func noteCard(_ entry: LibraryEntry, note: TextNote) -> some View {
        let isCopied = copiedID == entry.id
        let smartType = TextIntelligence.detect(note.content)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 8) {
                // 顶部：类型标签 + 来源应用 + 收藏星标 + 查看/编辑
                HStack(spacing: 5) {
                    typeBadge(smartType)

                    if let source = note.sourceApp, !source.isEmpty {
                        Text(source)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.75))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.04)))
                            .lineLimit(1)
                    }

                    Spacer()

                    FavoriteStarButton(isFavorite: entry.isFavorite) {
                        toggleNoteFavorite(note)
                    }

                    Button {
                        inspectingNote = note
                    } label: {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(LensoColors.kleinBlueSoft))
                    }
                    .buttonStyle(.plain)
                    .help("查看全文与格式化")

                    Menu {
                        Button("编辑便签") {
                            draft = note.content
                            editingNote = note
                        }
                        Button("删除便签", role: .destructive) {
                            delete(note)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                // 卡片正文主体：自适应网址、代码与常规文字
                switch smartType {
                case .url(let url, let origStr):
                    let title = webStore.title(for: origStr) ?? url.host ?? origStr

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.92))
                            .lineLimit(2)

                        if let host = url.host {
                            Text(host)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(LensoColors.kleinBlueBright)
                                .lineLimit(1)
                        }

                        Spacer()

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
                            .padding(.vertical, 4)
                            .background(Capsule().fill(LensoColors.kleinBlueBright))
                        }
                        .buttonStyle(.plain)
                        .help("在默认浏览器中打开此网页")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear {
                        webStore.fetchTitleIfNeeded(for: origStr)
                    }

                case .json(let pretty, _):
                    Text(pretty)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(red: 0.15, green: 0.2, blue: 0.3))
                        .lineSpacing(2)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                case .code(_, let formatted):
                    Text(formatted)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(red: 0.15, green: 0.2, blue: 0.3))
                        .lineSpacing(2)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                case .plainText:
                    Text(note.content.isEmpty ? "（空白）" : note.content)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.88))
                        .lineSpacing(3)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                Divider().opacity(0.5)

                // 底部时间（年月日时分秒）与一键复制
                HStack {
                    Text(timeText(entry.date))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        copy(note, entry: entry)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc")
                            Text("复制")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(LensoColors.kleinBlueSoft))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            // 复制成功的覆盖动效反馈
            if isCopied {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.green)
                        Text("已复制")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                }
                .transition(.opacity)
            }
        }
        .frame(height: 185)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { copy(note, entry: entry) }
    }

    @ViewBuilder
    private func typeBadge(_ type: TextIntelligence.ContentType) -> some View {
        switch type {
        case .url:
            HStack(spacing: 3) {
                Image(systemName: "globe")
                Text("网页")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(LensoColors.kleinBlueBright)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(LensoColors.kleinBlueSoft))

        case .json:
            HStack(spacing: 3) {
                Image(systemName: "curlybraces")
                Text("JSON")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(LensoColors.kleinBlueBright)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(LensoColors.kleinBlueSoft))

        case .code(let lang, _):
            HStack(spacing: 3) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text(lang)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(LensoColors.kleinBlueBright)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(LensoColors.kleinBlueSoft))

        case .plainText:
            Image(systemName: "text.quote")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LensoColors.kleinBlueBright)
        }
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

    private func timeText(_ date: Date) -> String {
        DateFormatter.lensoFullDateTime.string(from: date)
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
