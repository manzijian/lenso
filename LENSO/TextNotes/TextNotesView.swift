import SwiftUI
import AppKit

/// 文字收纳 — 收藏、查看、复制、编辑、删除文字片段
struct TextNotesView: View {
    @State private var notes: [TextNote] = []
    @State private var editing: TextNote?
    @State private var draft = ""
    @State private var copiedID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            header
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editing) { note in
            NoteEditorSheet(
                text: $draft,
                onCancel: { editing = nil },
                onSave: {
                    try? ScreenshotStore.shared.updateTextNote(id: note.id, content: draft)
                    editing = nil
                    reload()
                    NotificationCenter.default.post(name: .textNotesChanged, object: nil)
                }
            )
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .textNotesChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryChanged)) { _ in reload() }
    }

    private var header: some View {
        HStack {
            Text("文字").font(.system(size: 15, weight: .semibold))
            Text("\(notes.count) 条").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button {
                createNote()
            } label: {
                Label("新建", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(LensoColors.kleinBlueBright))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var content: some View {
        if notes.isEmpty {
            ContentUnavailableView(
                "还没有文字收纳",
                systemImage: "text.alignleft",
                description: Text("复制的文字可在「剪贴板历史」里收藏，或点右上角新建")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(notes) { note in
                        noteCard(note)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func noteCard(_ note: TextNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.content.isEmpty ? "（空白）" : note.content)
                .font(.system(size: 13))
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                if let source = note.sourceApp {
                    Label(source, systemImage: "app")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(note.updatedAt, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if copiedID == note.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                } else {
                    cardAction("doc.on.doc", "复制") { copy(note) }
                }
                cardAction(
                    note.isFavorite ? "star.fill" : "star",
                    note.isFavorite ? "取消收藏" : "收藏",
                    tint: note.isFavorite ? .yellow : nil
                ) {
                    toggleFavorite(note)
                }
                cardAction("pencil", "编辑") {
                    draft = note.content
                    editing = note
                }
                cardAction("trash", "删除", danger: true) { delete(note) }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 4, y: 1)
        )
    }

    private func cardAction(
        _ icon: String,
        _ label: String,
        danger: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint ?? (danger ? .red : .secondary))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func reload() {
        notes = (try? ScreenshotStore.shared.listTextNotes()) ?? []
    }

    private func createNote() {
        guard let note = try? ScreenshotStore.shared.createTextNote(
            content: "",
            sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName
        ) else { return }
        reload()
        NotificationCenter.default.post(name: .textNotesChanged, object: nil)
        draft = ""
        editing = note
    }

    private func copy(_ note: TextNote) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.content, forType: .string)
        ClipboardMonitor.shared.markSelfWrite()
        SaveToastController.shared.show(title: "已复制", subtitle: "到剪贴板", thumbnail: nil)
        copiedID = note.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run { if copiedID == note.id { copiedID = nil } }
        }
    }

    private func delete(_ note: TextNote) {
        try? ScreenshotStore.shared.deleteTextNote(id: note.id)
        reload()
        NotificationCenter.default.post(name: .textNotesChanged, object: nil)
    }

    private func toggleFavorite(_ note: TextNote) {
        try? ScreenshotStore.shared.setTextNoteFavorite(!note.isFavorite, id: note.id)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
        reload()
    }
}

extension Notification.Name {
    static let textNotesChanged = Notification.Name("com.lenso.textNotesChanged")
}
