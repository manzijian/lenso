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
    @State private var selection: UUID?
    @State private var columnCount: Int = 5
    @State private var confirmingClear = false
    @State private var savedNoteIDs: Set<UUID> = []
    @State private var inspectingItem: Item?
    @State private var keyMonitor: Any?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gridSpacing: CGFloat = 10

    var body: some View {
        VStack(spacing: 10) {
            header
            content
                .lensoAnimation(LensoAnimations.fade, value: items.isEmpty, reduceMotion: reduceMotion)
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
        .overlay {
            inspectionOverlay
        }
        .lensoColorScheme()
        .onAppear {
            reload()
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("剪贴板历史").font(.system(size: 15, weight: .semibold))
            Spacer()

            if !items.isEmpty {
                Group {
                    if confirmingClear {
                        HStack(spacing: 6) {
                            Button {
                                LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                                    confirmingClear = false
                                }
                            } label: {
                                Text("取消")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.black.opacity(0.05)))
                            }
                            .buttonStyle(LensoPressButtonStyle())

                            Button {
                                try? ScreenshotStore.shared.clearClipboardHistory()
                                LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                                    confirmingClear = false
                                    selection = nil
                                }
                                reload()
                            } label: {
                                Text("确认清空?")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.red.opacity(0.85)))
                            }
                            .buttonStyle(LensoPressButtonStyle())
                        }
                        .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                    } else {
                        Button {
                            LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                                confirmingClear = true
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(3))
                                await MainActor.run {
                                    LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                                        confirmingClear = false
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                Text("清空历史")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.045)))
                        }
                        .buttonStyle(LensoPressButtonStyle())
                        .help("清空历史")
                        .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                    }
                }
                .lensoAnimation(LensoAnimations.snappy, value: confirmingClear, reduceMotion: reduceMotion)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(LensoPressButtonStyle())
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
            .transition(.opacity)
        } else {
            GeometryReader { geo in
                let cols = max(1, Int((geo.size.width + gridSpacing) / (130 + gridSpacing)))
                let gridColumns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: cols)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                            ForEach(items) { item in
                                ClipboardCellView(
                                    item: item,
                                    isSelected: selection == item.id,
                                    isCopied: copiedID == item.id,
                                    isSavedNote: savedNoteIDs.contains(item.id),
                                    onSelectAndCopy: {
                                        selection = item.id
                                        copyBack(item)
                                    },
                                    onFormatJSON: { formatJSON(item) },
                                    onSaveAsNote: { saveAsNote(item) }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: selection) { _, newValue in
                        guard let newValue else { return }
                        LensoAnimations.withMotion(LensoAnimations.hover, reduceMotion: reduceMotion) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
                .onAppear { columnCount = cols }
                .onChange(of: cols) { _, newCols in columnCount = newCols }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var inspectionOverlay: some View {
        if let item = inspectingItem {
            ZStack {
                Color.black.opacity(0.36)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                            inspectingItem = nil
                        }
                    }

                Group {
                    switch item.kind {
                    case .text:
                        TextDetailInspectorSheet(
                            rawContent: item.text ?? "",
                            sourceApp: item.sourceApp,
                            createdAt: item.createdAt,
                            onDismiss: {
                                LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                                    inspectingItem = nil
                                }
                            }
                        )
                        .frame(width: 660, height: 390)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.28), radius: 20, y: 8)

                    case .image:
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(LensoColors.kleinBlueBright)
                                Text("图片预览")
                                    .font(.system(size: 12.5, weight: .bold))
                                if let app = item.sourceApp, !app.isEmpty {
                                    Text(app)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.black.opacity(0.05)))
                                }
                                Spacer()
                                Button {
                                    copyBack(item)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedID == item.id ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10))
                                            .lensoSymbolReplace()
                                        Text(copiedID == item.id ? "已复制" : "复制")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundStyle(copiedID == item.id ? Color.green : Color.primary.opacity(0.85))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.black.opacity(0.06)))
                                }
                                .buttonStyle(LensoPressButtonStyle())

                                Button {
                                    LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                                        inspectingItem = nil
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(LensoPressButtonStyle())
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white)

                            Divider()

                            ZStack {
                                Color(red: 0.95, green: 0.955, blue: 0.97)
                                if let image = item.image {
                                    Image(decorative: image, scale: 1)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .padding(16)
                                } else {
                                    Text("无法加载图片内容")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(width: 640, height: 390)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.28), radius: 20, y: 8)
                    }
                }
                .transition(LensoTransitions.overlayCard(reduceMotion: reduceMotion))
            }
            .transition(.opacity)
        }
    }

    // MARK: - 键盘导航

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                if inspectingItem != nil {
                    if let responder = NSApp.keyWindow?.firstResponder as? NSTextView,
                       responder.hasMarkedText() {
                        return event
                    }
                    LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                        inspectingItem = nil
                    }
                } else if confirmingClear {
                    LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                        confirmingClear = false
                    }
                } else {
                    onDismiss()
                }
                return nil
            }

            if inspectingItem != nil {
                if let responder = NSApp.keyWindow?.firstResponder as? NSTextView {
                    if event.keyCode == 53, !responder.hasMarkedText() {
                        LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                            inspectingItem = nil
                        }
                        return nil
                    }
                    return event
                }
                if event.keyCode == 49 { // Space 关闭预览
                    LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                        inspectingItem = nil
                    }
                    return nil
                }
                if [123, 124, 125, 126, 36, 76].contains(event.keyCode) {
                    return nil
                }
                return event
            }

            switch event.keyCode {
            case 123: moveSelection(-1); return nil
            case 124: moveSelection(1); return nil
            case 125: moveSelection(columnCount); return nil
            case 126: moveSelection(-columnCount); return nil
            case 36, 76: // Return / Enter
                if let item = selectedOrFirstItem() {
                    selection = item.id
                    copyBack(item)
                }
                return nil
            case 49: // Space
                if let item = selectedOrFirstItem() {
                    selection = item.id
                    LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                        inspectingItem = item
                    }
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        guard let current = selection,
              let index = items.firstIndex(where: { $0.id == current }) else {
            selection = items[min(max(0, delta), items.count - 1)].id
            return
        }
        let next = min(max(0, index + delta), items.count - 1)
        selection = items[next].id
    }

    private func selectedOrFirstItem() -> Item? {
        if let current = selection, let hit = items.first(where: { $0.id == current }) {
            return hit
        }
        return items.first
    }

    private func reload() {
        Task {
            let result = await Self.loadItems()
            items = result.items
            savedNoteIDs = result.savedNoteIDs
            if selection == nil || !items.contains(where: { $0.id == selection }) {
                selection = items.first?.id
            }
        }
    }

    private struct ClipboardLoadResult: @unchecked Sendable {
        let items: [Item]
        let savedNoteIDs: Set<UUID>
    }

    /// 历史记录与图片解码放到主线程之外，面板可以先即时弹出。
    nonisolated private static func loadItems() async -> ClipboardLoadResult {
        let store = ScreenshotStore.shared
        let records = (try? store.listClipboard()) ?? []
        let noteTexts = Set(((try? store.listTextNotes()) ?? []).map(\.content))
        var savedIDs = Set<UUID>()

        let items = records.map { record -> Item in
            let text = record.text
            if let text, noteTexts.contains(text) {
                savedIDs.insert(record.id)
            }
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
        return ClipboardLoadResult(items: items, savedNoteIDs: savedIDs)
    }

    /// 把文字条目收藏到「文字收纳」
    private func saveAsNote(_ item: Item) {
        guard let text = item.text, !savedNoteIDs.contains(item.id) else { return }
        _ = try? ScreenshotStore.shared.createTextNote(content: text, sourceApp: item.sourceApp)
        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
            savedNoteIDs.insert(item.id)
        }
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

private struct ClipboardCellView: View {
    let item: ClipboardPanelView.Item
    let isSelected: Bool
    let isCopied: Bool
    let isSavedNote: Bool
    let onSelectAndCopy: () -> Void
    let onFormatJSON: () -> Void
    let onSaveAsNote: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let todayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()

    private static let otherDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm"
        return df
    }()

    private var compactTime: String {
        if Calendar.current.isDateInToday(item.createdAt) {
            return Self.todayFormatter.string(from: item.createdAt)
        }
        return Self.otherDayFormatter.string(from: item.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
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
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelectAndCopy() }

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
                if isCopied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .lensoSymbolReplace()
                } else {
                    Text(compactTime)
                        .font(.system(size: 9.5, design: .monospaced))
                        .lineLimit(1)
                }
                if item.isJSON {
                    Button(action: onFormatJSON) {
                        Image(systemName: "curlybraces")
                            .foregroundStyle(LensoColors.kleinBlueBright)
                    }
                    .buttonStyle(LensoPressButtonStyle())
                    .help("在 JSON 工作台中格式化")
                }
                if item.kind == .text {
                    Button(action: onSaveAsNote) {
                        Image(systemName: isSavedNote ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isSavedNote ? LensoColors.kleinBlueBright : .secondary)
                            .lensoSymbolReplace()
                    }
                    .buttonStyle(LensoPressButtonStyle())
                    .help(isSavedNote ? "已收藏到文字收纳" : "收藏到文字收纳")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(hovering ? 0.92 : 0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected ? LensoColors.kleinBlueBright : Color.black.opacity(hovering ? 0.14 : 0.06),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
        )
        .shadow(color: .black.opacity(hovering ? 0.10 : 0.03), radius: hovering ? 8 : 3, y: hovering ? 3 : 1)
        .offset(y: hovering && !reduceMotion ? -1.5 : 0)
        .lensoAnimation(LensoAnimations.hover, value: hovering, reduceMotion: reduceMotion)
        .lensoAnimation(LensoAnimations.hover, value: isSelected, reduceMotion: reduceMotion)
        .onHover { hovering = $0 }
        .help("点击复制这一条（Space 预览）")
    }
}
