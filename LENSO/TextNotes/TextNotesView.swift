import SwiftUI
import AppKit

/// 文字收纳 — 以现代化卡片网格流展示所有收纳的文字、代码、JSON 与网页链接
struct TextNotesView: View {
    @State private var notes: [TextNote] = []
    @State private var editing: TextNote?
    @State private var inspecting: TextNote?
    @State private var draft = ""
    @State private var copiedID: UUID?
    @ObservedObject private var webStore = WebMetadataStore.shared

    private let gridColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 12) {
            header
            content
        }
        .padding(14)
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
                Text("\(notes.count) 条卡片")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("自适应卡片相册流 · 支持代码高亮/格式化/网页识别")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var content: some View {
        if notes.isEmpty {
            ContentUnavailableView(
                "还没有文字收纳卡片",
                systemImage: "text.alignleft",
                description: Text("复制的文字或截图 OCR 提取的内容会自动在此生成卡片收纳")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(notes) { note in
                        noteCard(note)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 独立方块卡片

    private func noteCard(_ note: TextNote) -> some View {
        let isCopied = copiedID == note.id
        let smartType = TextIntelligence.detect(note.content)

        return ZStack(alignment: .topLeading) {
            // 卡片白色圆角底板
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 8) {
                // 顶部：智能类型徽章 + 来源应用 + 收藏星标 + 快捷操作
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

                    // 星标收藏
                    Button {
                        toggleFavorite(note)
                    } label: {
                        Image(systemName: note.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundStyle(note.isFavorite ? Color.yellow : Color.secondary.opacity(0.6))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(note.isFavorite ? "取消收藏" : "星标收藏")

                    // 详情 / 格式化 / 全文查看按钮
                    Button {
                        inspecting = note
                    } label: {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(LensoColors.kleinBlueSoft))
                    }
                    .buttonStyle(.plain)
                    .help("查看全文与格式化")

                    // 编辑菜单
                    Menu {
                        Button("编辑内容") {
                            draft = note.content
                            editing = note
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

                // 底部时间（年月日时分秒）与复制动作
                HStack {
                    Text(DateFormatter.lensoFullDateTime.string(from: note.updatedAt))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // 一键复制
                    Button {
                        copy(note)
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
        .onTapGesture { copy(note) }
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

    // MARK: - 操作

    private func reload() {
        notes = (try? ScreenshotStore.shared.listTextNotes()) ?? []
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
