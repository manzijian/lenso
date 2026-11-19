import SwiftUI
import AppKit

/// 剪贴板历史面板：图片网格 + 文字卡片，点击重新复制
struct ClipboardPanelView: View {
    var onDismiss: () -> Void = {}

    struct Item: Identifiable {
        let id: UUID
        let kind: ClipboardItem.Kind
        let image: CGImage?
        let text: String?
        let sourceApp: String?
        let createdAt: Date
        let isJSON: Bool
    }

    @State private var items: [Item] = []
    @State private var copiedID: UUID?

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 10)]

    var body: some View {
        VStack(spacing: 10) {
            header
            content
        }
        .padding(16)
        .frame(width: 760, height: 460)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .lensoColorScheme()
        .onAppear(perform: reload)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("剪贴板历史").font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                try? ScreenshotStore.shared.clearClipboardHistory()
                reload()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("清空历史")

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭（Esc）")
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "还没有剪贴板记录",
                systemImage: "doc.on.clipboard",
                description: Text("复制过的截图和文字会自动出现在这里")
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        cell(item)
                    }
                }
            }
        }
    }

    private func cell(_ item: Item) -> some View {
        Button {
            copyBack(item)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                if let image = item.image {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 84)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(item.text ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.9)))
                }
                HStack(spacing: 4) {
                    Image(systemName: item.kind == .image ? "photo" : "text.alignleft")
                    if item.isJSON {
                        Text("JSON")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(LensoColors.kleinBlueSoft))
                    }
                    Text(item.sourceApp ?? "LENSO")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 2)
                    if copiedID == item.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text(DateFormatter.lensoFullDateTime.string(from: item.createdAt))
                    }
                    if item.isJSON {
                        Button {
                            formatJSON(item)
                        } label: {
                            Image(systemName: "curlybraces")
                                .foregroundStyle(LensoColors.kleinBlueBright)
                        }
                        .buttonStyle(.plain)
                        .help("在 JSON 工作台中格式化")
                    }
                    if item.kind == .text {
                        Button {
                            saveAsNote(item)
                        } label: {
                            Image(systemName: "bookmark")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("收藏到文字收纳")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.65))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.black.opacity(0.06), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击复制这一条")
    }

    private func reload() {
        Task {
            let result = await Self.loadItems()
            items = result.items
        }
    }

    private struct ClipboardLoadResult: @unchecked Sendable {
        let items: [Item]
    }

    /// 历史记录与图片解码放到主线程之外，面板可以先即时弹出。
    nonisolated private static func loadItems() async -> ClipboardLoadResult {
        let store = ScreenshotStore.shared
        let records = (try? store.listClipboard()) ?? []
        let items = records.map { record -> Item in
            let text = record.text
            return Item(
                id: record.id,
                kind: record.kind,
                image: record.kind == .image ? store.loadClipboardImage(record) : nil,
                text: text,
                sourceApp: record.sourceApp,
                createdAt: record.createdAt,
                isJSON: text.map(JSONClipboard.looksLikeJSON) ?? false
            )
        }
        return ClipboardLoadResult(items: items)
    }

    /// 把文字条目收藏到「文字收纳」
    private func saveAsNote(_ item: Item) {
        guard let text = item.text else { return }
        _ = try? ScreenshotStore.shared.createTextNote(content: text, sourceApp: item.sourceApp)
        NotificationCenter.default.post(name: .textNotesChanged, object: nil)
        SaveToastController.shared.show(title: "已收藏", subtitle: "到文字收纳", thumbnail: nil)
    }

    /// 在 JSON 工作台里打开这条内容（自动格式化）
    private func formatJSON(_ item: Item) {
        guard let text = item.text else { return }
        onDismiss()
        ToolHostWindowController.shared.show(toolID: "json", initialText: text)
    }

    private func copyBack(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = item.image,
           let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        } else if let text = item.text {
            pasteboard.setString(text, forType: .string)
        }
        ClipboardMonitor.shared.markSelfWrite()
        SaveToastController.shared.show(title: "已复制", subtitle: "到剪贴板", thumbnail: item.image)
        copiedID = item.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                if copiedID == item.id { copiedID = nil }
            }
        }
    }
}
