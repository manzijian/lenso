import SwiftUI
import AppKit

/// Spotlight 风格搜索（参考图 4 顶部）：居中胶囊 + 展开结果
struct SearchPanelView: View {
    var onDismiss: () -> Void = {}

    @State private var searchText = ""
    @FocusState private var focused: Bool

    struct SearchResult: Identifiable {
        let id: UUID          // 对应截图记录 ID
        let title: String
        let appName: String
        let snippet: String
        let thumbnail: CGImage?
    }

    @State private var results: [SearchResult] = []
    @State private var hoveredID: UUID?
    @State private var copiedID: UUID?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            // 搜索胶囊
            LensoMaterials.glassContainer {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("搜索截图、图片或关键词…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focused)

                    if let first = results.first, let thumb = first.thumbnail {
                        Image(decorative: thumb, scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 38, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }

                    Image(systemName: "return")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.primary.opacity(0.06)))

                    // 关闭
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("关闭搜索（Esc）")
                }
                .padding(.horizontal, 18)
                .frame(height: 60)
                .glassEffect(.regular, in: Capsule())
            }

            // 结果
            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results) { result in
                        HStack(spacing: 12) {
                            if let thumb = result.thumbnail {
                                Image(decorative: thumb, scale: 2)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 42)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).font(.system(size: 13, weight: .medium))
                                Text(result.snippet)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()

                            // 复制反馈 / 查看按钮
                            if copiedID == result.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.green)
                                    .frame(width: 28, height: 24)
                            } else {
                                ResultAction(icon: "eye", label: "查看") {
                                    openWindow(id: "preview", value: result.id)
                                    onDismiss()
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        // 默认单击 = 复制
                        .onTapGesture { copy(result) }
                    }
                }
                .padding(.vertical, 6)
                .background {
                    if #available(macOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .onAppear {
            focused = true
            updateResults()
        }
        .onChange(of: searchText) { _ in updateResults() }
        .onExitCommand { onDismiss() }
        .environment(\.colorScheme, .light)
    }

    private func updateResults() {
        let store = ScreenshotStore.shared
        let records = (try? store.list()) ?? []
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        let matched = keyword.isEmpty ? records.prefix(4) : records.filter {
            $0.filename.localizedCaseInsensitiveContains(keyword)
        }.prefix(8)
        results = matched.map { record in
            SearchResult(
                id: record.id,
                title: record.filename,
                appName: "LENSO",
                snippet: "\(record.width) × \(record.height) · \(byteString(record.fileSize))",
                thumbnail: store.loadThumbnail(record)
            )
        }
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// 复制原图到剪贴板（单击结果的默认行为）
    private func copy(_ result: SearchResult) {
        let store = ScreenshotStore.shared
        let records = (try? store.list()) ?? []
        guard let record = records.first(where: { $0.id == result.id }),
              let image = store.loadImage(record) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        SaveToastController.shared.show(title: "已复制", subtitle: "到剪贴板", thumbnail: image)
        copiedID = result.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                if copiedID == result.id { copiedID = nil }
            }
        }
    }
}

/// 搜索结果行内的操作按钮
private struct ResultAction: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(hovering ? Color(nsColor: .controlAccentColor) : .secondary)
            .frame(width: 28, height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color(nsColor: .controlAccentColor).opacity(0.12) : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { action() }
            .help(label)
    }
}
