import SwiftUI
import AppKit

/// 「最近」「收藏」的时间倒序混排列表
struct LibraryFeedView: View {
    let entries: [LibraryEntry]
    let emptyTitle: String
    let emptyMessage: String
    let emptyIcon: String

    @Environment(\.openWindow) private var openWindow
    @State private var editingNote: TextNote?
    @State private var draft = ""
    @State private var copiedID: String?

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
                    LazyVStack(spacing: 10) {
                        ForEach(entries) { entry in
                            if let record = entry.screenshot {
                                screenshotRow(entry, record: record)
                            } else if let note = entry.note {
                                noteRow(entry, note: note)
                            }
                        }
                    }
                    .padding(.vertical, 2)
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
    }

    // MARK: - Rows

    private func screenshotRow(_ entry: LibraryEntry, record: ScreenshotRecord) -> some View {
        HStack(spacing: 12) {
            Button {
                openFloatingPreview(record)
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if let thumbnail = entry.thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.primary.opacity(0.06)
                        }
                    }
                    .frame(width: 120, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.filename)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(record.width) × \(record.height) · \(timeText(entry.date))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开预览")

            FavoriteStarButton(isFavorite: entry.isFavorite) {
                toggleScreenshotFavorite(record)
            }
        }
        .padding(10)
        .background(rowBackground)
    }

    private func noteRow(_ entry: LibraryEntry, note: TextNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.7)))

            VStack(alignment: .leading, spacing: 6) {
                Text(note.content.isEmpty ? "（空白）" : note.content)
                    .font(.system(size: 12))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if let source = note.sourceApp {
                        Label(source, systemImage: "app")
                            .lineLimit(1)
                    }
                    Text(timeText(entry.date))
                    Spacer()
                    if copiedID == entry.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    } else {
                        actionButton("doc.on.doc", "复制") { copy(note, entry: entry) }
                    }
                    actionButton("pencil", "编辑") {
                        draft = note.content
                        editingNote = note
                    }
                    actionButton("trash", "删除", danger: true) { delete(note) }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            FavoriteStarButton(isFavorite: entry.isFavorite) {
                toggleNoteFavorite(note)
            }
        }
        .padding(10)
        .background(rowBackground)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 4, y: 1)
    }

    private func actionButton(
        _ icon: String,
        _ label: String,
        danger: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(danger ? .red : .secondary)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Actions

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

    private func copy(_ note: TextNote, entry: LibraryEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.content, forType: .string)
        ClipboardMonitor.shared.markSelfWrite()
        SaveToastController.shared.show(title: "已复制", subtitle: "到剪贴板", thumbnail: nil)
        copiedID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                if copiedID == entry.id { copiedID = nil }
            }
        }
    }
}
