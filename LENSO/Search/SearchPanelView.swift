import SwiftUI
import AppKit

/// 通用中文完整日期时间格式化工具：统一输出「年月日时分秒」
extension DateFormatter {
    static let lensoFullDateTime: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy年MM月dd日 HH:mm:ss"
        df.locale = Locale(identifier: "zh_CN")
        return df
    }()
}

extension Date {
    /// 与截图一致的相对日期时间：今日 / 昨日 / M月d日 / yyyy年M月d日，均带时分秒
    var lensoRelativeDayTime: String {
        let calendar = Calendar.current
        let time = formatted(date: .omitted, time: .standard)
        if calendar.isDateInToday(self) { return "今日 \(time)" }
        if calendar.isDateInYesterday(self) { return "昨日 \(time)" }
        if calendar.component(.year, from: self) == calendar.component(.year, from: .now) {
            return "\(formatted(.dateTime.month(.defaultDigits).day())) \(time)"
        }
        return "\(formatted(.dateTime.year().month(.defaultDigits).day())) \(time)"
    }
}

// MARK: - 桌面毛玻璃背景

/// 跨窗口毛玻璃：模糊面板背后的真实桌面（而不是面板内部内容）
struct BehindWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

// MARK: - 沉浸式搜索面板

/// 全屏沉浸式搜索：模糊桌面 + 瀑布流画廊（参考 Apple 照片搜索）
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
        /// 截图条目保留记录，全尺寸图在预览/复制时按需加载
        let record: ScreenshotRecord?
    }

    @State private var searchText = ""
    @State private var selectedCategory: FilterCategory = .all
    @State private var items: [FeedItem] = []
    @State private var copiedID: UUID?
    @State private var inspectingItem: FeedItem?
    @State private var selection: UUID?
    @State private var currentColumnCount = 6
    @State private var keyMonitor: Any?
    @ObservedObject private var webStore = WebMetadataStore.shared
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var categoryNamespace

    private let gap: CGFloat = 11
    private let sidePadding: CGFloat = 22
    /// 所有卡片统一高度，不随截图比例变化
    private static let tileHeight: CGFloat = 148

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // 与主界面同一套浅色底：磨砂桌面 + 极浅冷色渐变
            ZStack {
                BehindWindowBlur()
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.94),
                        Color(red: 0.973, green: 0.976, blue: 0.986).opacity(0.96),
                        Color(red: 0.958, green: 0.966, blue: 0.984).opacity(0.97)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .top) {
            // 顶部留白区域作为拖动带：按住可移动整个搜索窗口
            SearchPanelDragStrip()
                .frame(height: 18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 30, y: 14)
        .onAppear {
            focused = true
            reloadFeed()
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: .searchPanelShouldReload)) { _ in
            focused = true
            reloadFeed()
        }
        .onReceive(NotificationCenter.default.publisher(for: .textNotesChanged)) { _ in reloadFeed() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryChanged)) { _ in reloadFeed() }
        .onReceive(NotificationCenter.default.publisher(for: .screenshotSaved)) { _ in reloadFeed() }
        .onChange(of: items.map(\.id)) { _, _ in
            if selection == nil { selection = filteredItems.first?.id }
        }
        .onExitCommand {
            if inspectingItem != nil {
                LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                    inspectingItem = nil
                }
            } else {
                onDismiss()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchPanelEscapePressed)) { _ in
            if inspectingItem != nil {
                LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                    inspectingItem = nil
                }
            } else {
                onDismiss()
            }
        }
        .overlay {
            SearchPanelInspectionOverlay(
                item: $inspectingItem,
                onCopyItem: { copyItem($0) },
                onPinImage: { openFloatingPreview($0) }
            )
        }
    }

    // MARK: - 顶部搜索与筛选

    private func openJSONTool() {
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        ToolHostWindowController.shared.show(toolID: "json", initialText: clip)
    }

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LensoColors.kleinBlue.opacity(0.8))

                ZStack(alignment: .leading) {
                    if searchText.isEmpty {
                        Text("搜索截图、复制文字、来源应用…")
                            .font(.system(size: 16.5))
                            .foregroundStyle(Color.black.opacity(0.3))
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16.5))
                        .foregroundStyle(Color.primary)
                        .focused($focused)
                        .onSubmit { copySelectedOrFirst() }
                }

                // JSON 工具快捷入口：取当前剪贴板文本作为初始内容
                Button {
                    openJSONTool()
                } label: {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .frame(width: 24, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.black.opacity(0.05))
                        )
                }
                .buttonStyle(LensoPressButtonStyle())
                .help("JSON 格式化工具")

                Group {
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.black.opacity(0.28))
                        }
                        .buttonStyle(LensoPressButtonStyle())
                        .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                    } else {
                        Text("esc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.42))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                            )
                            .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                    }
                }
                .lensoAnimation(LensoAnimations.snappy, value: searchText.isEmpty, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .frame(maxWidth: 620)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        focused ? LensoColors.kleinBlueBright.opacity(0.55) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
                    .lensoAnimation(LensoAnimations.hover, value: focused, reduceMotion: reduceMotion)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)

            HStack(spacing: 7) {
                ForEach(FilterCategory.allCases) { cat in
                    let active = selectedCategory == cat
                    Button {
                        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                            selectedCategory = cat
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(cat.rawValue)
                                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                            Text("\(count(for: cat))")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .opacity(active ? 0.7 : 0.55)
                                .lensoNumericTransition()
                        }
                        .foregroundStyle(active ? Color.white : Color.black.opacity(0.62))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background {
                            if active {
                                Capsule()
                                    .fill(LensoColors.kleinBlue)
                                    .matchedGeometryEffect(id: "activeCategoryPill", in: categoryNamespace)
                            } else {
                                Capsule()
                                    .fill(Color.black.opacity(0.045))
                            }
                        }
                    }
                    .buttonStyle(LensoPressButtonStyle())
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.black.opacity(0.045)))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(LensoPressButtonStyle())
            .help("关闭搜索 (Esc)")
        }
        .padding(.horizontal, sidePadding)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - 瀑布流内容

    private var content: some View {
        GeometryReader { geo in
            let available = geo.size.width - sidePadding * 2
            let columns = columnCount(for: available)
            let gridColumns = Array(
                repeating: GridItem(.flexible(), spacing: gap, alignment: .top),
                count: columns
            )

            ScrollViewReader { proxy in
                ScrollView {
                    if filteredItems.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(daySections) { section in
                                VStack(alignment: .leading, spacing: 11) {
                                    sectionHeader(section)

                                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gap) {
                                        ForEach(section.items) { item in
                                            tile(item)
                                                .id(item.id)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, sidePadding)
                        .padding(.top, 2)
                        .padding(.bottom, 26)
                    }
                }
                .onChange(of: selection) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onAppear { currentColumnCount = columns }
                .onChange(of: columns) { _, newValue in currentColumnCount = newValue }
            }
        }
    }

    private var emptyState: some View {
        let state: (symbol: String, title: String, subtitle: String) = {
            if !searchText.isEmpty {
                return ("magnifyingglass", "未找到匹配的内容", "试试更换关键词")
            }
            switch selectedCategory {
            case .all:
                return ("photo.stack", "暂无最近复制记录", "截取图片或复制任意文字，都会在这里形成画廊")
            case .images:
                return ("photo", "暂无图片记录", "截取屏幕或复制图片后，会显示在这里")
            case .text:
                return ("text.quote", "暂无文本记录", "复制文字或收纳便签后，会显示在这里")
            }
        }()

        return VStack(spacing: 12) {
            Image(systemName: state.symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.black.opacity(0.18))
            Text(state.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.62))
            Text(state.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func sectionHeader(_ section: DaySection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.title)
                .font(.system(size: 16.5, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.82))
            Text("\(section.items.count) 项")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - 单块内容

    @ViewBuilder
    private func tile(_ item: FeedItem) -> some View {
        let openAction = {
            LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                inspectingItem = item
            }
        }
        switch item.kind {
        case .image(let cgImage, _):
            ImmersiveImageTile(
                item: item,
                image: cgImage,
                height: Self.tileHeight,
                isSelected: selection == item.id,
                isCopied: copiedID == item.id,
                onSelect: { selection = item.id },
                onOpen: openAction,
                onCopy: { copyItem(item) }
            )
        case .text(let content):
            ImmersiveTextTile(
                item: item,
                content: content,
                height: Self.tileHeight,
                isSelected: selection == item.id,
                isCopied: copiedID == item.id,
                onSelect: { selection = item.id },
                onOpen: openAction,
                onCopy: { copyItem(item) }
            )
        }
    }

    // MARK: - 底部状态栏

    private var footer: some View {
        HStack(spacing: 16) {
            hint("↑↓←→", "选择")
            hint("↵", "复制")
            hint("space", "预览")
            hint("esc", "关闭")
            Spacer()
            Text("共 \(filteredItems.count) 项")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, sidePadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                )
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 瀑布流布局计算

    private struct DaySection: Identifiable {
        let id: TimeInterval
        let title: String
        let items: [FeedItem]
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        var order: [TimeInterval] = []
        var buckets: [TimeInterval: [FeedItem]] = [:]

        for item in filteredItems {
            let day = calendar.startOfDay(for: item.createdAt)
            let key = day.timeIntervalSince1970
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(item)
        }

        return order.map { key in
            let date = Date(timeIntervalSince1970: key)
            let title: String
            if calendar.isDateInToday(date) {
                title = "今天"
            } else if calendar.isDateInYesterday(date) {
                title = "昨天"
            } else if calendar.component(.year, from: date) == calendar.component(.year, from: .now) {
                title = date.formatted(.dateTime.month(.defaultDigits).day())
            } else {
                title = date.formatted(.dateTime.year().month(.defaultDigits).day())
            }
            return DaySection(id: key, title: title, items: buckets[key] ?? [])
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        let target: CGFloat = 205
        let count = Int((width + gap) / (target + gap))
        return max(3, min(7, count))
    }

    // MARK: - 过滤逻辑

    private func matches(_ item: FeedItem, category: FilterCategory) -> Bool {
        switch category {
        case .all: break
        case .text:
            if case .image = item.kind { return false }
        case .images:
            if case .text = item.kind { return false }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return true }
        if item.title.localizedCaseInsensitiveContains(query) { return true }
        if item.subtitle.localizedCaseInsensitiveContains(query) { return true }
        if let raw = item.rawText, raw.localizedCaseInsensitiveContains(query) { return true }
        if let app = item.sourceApp, app.localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    private func count(for category: FilterCategory) -> Int {
        items.reduce(0) { $0 + (matches($1, category: category) ? 1 : 0) }
    }

    private var filteredItems: [FeedItem] {
        items.filter { matches($0, category: selectedCategory) }
    }

    // MARK: - 键盘导航

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 输入法组词期间全部放行，避免抢走候选框的方向键
            if let textView = event.window?.firstResponder as? NSTextView, textView.hasMarkedText() {
                return event
            }

            if inspectingItem != nil {
                switch event.keyCode {
                case 49, 53: // Space / Esc：关闭详情弹层
                    LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                        inspectingItem = nil
                    }
                    return nil
                case 123, 124, 125, 126, 36, 76: // 阻止方向键与回车修改后台选中态
                    return nil
                default:
                    return event
                }
            }

            switch event.keyCode {
            case 123: moveSelectionHorizontal(-1); return nil
            case 124: moveSelectionHorizontal(1); return nil
            case 125: moveSelectionVertical(down: true); return nil
            case 126: moveSelectionVertical(down: false); return nil
            case 36, 76: // Return / 小键盘 Enter
                if event.modifierFlags.contains(.command) {
                    openSelected()
                } else {
                    copySelectedOrFirst()
                }
                return nil
            case 49: // Space：快速预览选中项（输入框里打字时放行）
                if event.window?.firstResponder is NSTextView { return event }
                openSelected()
                return nil
            case 8: // ⌘C：复制选中项（输入框里放行，保留系统复制）
                guard event.modifierFlags.contains(.command),
                      !(event.window?.firstResponder is NSTextView) else { return event }
                copySelectedOrFirst()
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

    private func moveSelectionHorizontal(_ delta: Int) {
        let list = filteredItems
        guard !list.isEmpty else { return }
        guard let current = selection,
              let index = list.firstIndex(where: { $0.id == current }) else {
            selection = list[min(max(0, delta), list.count - 1)].id
            return
        }
        let next = min(max(0, index + delta), list.count - 1)
        selection = list[next].id
    }

    private func moveSelectionVertical(down: Bool) {
        let sections = daySections
        guard !sections.isEmpty else { return }
        let cols = max(1, currentColumnCount)

        guard let current = selection,
              let secIdx = sections.firstIndex(where: { $0.items.contains(where: { $0.id == current }) }),
              let itemIdx = sections[secIdx].items.firstIndex(where: { $0.id == current }) else {
            selection = sections.first?.items.first?.id
            return
        }

        let currentRow = itemIdx / cols
        let col = itemIdx % cols
        let secItems = sections[secIdx].items
        let lastRow = (secItems.count - 1) / cols

        if down {
            if currentRow < lastRow {
                let targetIdx = min(secItems.count - 1, (currentRow + 1) * cols + col)
                selection = secItems[targetIdx].id
            } else if secIdx + 1 < sections.count {
                let nextItems = sections[secIdx + 1].items
                let targetIdx = min(nextItems.count - 1, col)
                selection = nextItems[targetIdx].id
            }
        } else {
            if currentRow > 0 {
                let targetIdx = (currentRow - 1) * cols + col
                selection = secItems[targetIdx].id
            } else if secIdx > 0 {
                let prevItems = sections[secIdx - 1].items
                let prevLastRow = (prevItems.count - 1) / cols
                let targetIdx = min(prevItems.count - 1, prevLastRow * cols + col)
                selection = prevItems[targetIdx].id
            }
        }
    }

    private func copySelectedOrFirst() {
        if let current = selection, let item = filteredItems.first(where: { $0.id == current }) {
            copyItem(item)
        } else if let first = filteredItems.first {
            selection = first.id
            copyItem(first)
        }
    }

    private func openSelected() {
        if let current = selection, let item = filteredItems.first(where: { $0.id == current }) {
            LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                inspectingItem = item
            }
        } else if let first = filteredItems.first {
            LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                inspectingItem = first
            }
        }
    }

    // MARK: - 数据加载

    private struct FeedLoadResult: @unchecked Sendable {
        let items: [FeedItem]
    }

    private func reloadFeed() {
        Task {
            let result = await Self.buildFeed()
            items = result.items
            if selection == nil { selection = result.items.first?.id }
        }
    }

    /// 读盘与解码全部在 MainActor 之外完成；截图只取缩略图，全尺寸图按需加载。
    nonisolated private static func buildFeed() async -> FeedLoadResult {
        let store = ScreenshotStore.shared
        var feed: [FeedItem] = []
        var seenTexts = Set<String>()
        var seenImageHashes = Set<String>()
        /// 剪贴板里的图片：用于把「同一张图既是剪贴板图片又是截图记录」的旧数据去重
        var clipboardImages: [(width: Int, height: Int, at: Date)] = []

        // 1. 读取剪贴板历史（图文混合，最准确的复制时间流）
        if let clipItems = try? store.listClipboard(limit: 120) {
            for clip in clipItems {
                switch clip.kind {
                case .text:
                    if let text = clip.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if seenTexts.contains(text) { continue }
                        seenTexts.insert(text)

                        feed.append(FeedItem(
                            id: clip.id,
                            kind: .text(content: text),
                            title: text.replacingOccurrences(of: "\n", with: " "),
                            subtitle: "\(text.count) 个字符",
                            sourceApp: clip.sourceApp,
                            createdAt: clip.createdAt,
                            rawText: text,
                            thumbnail: nil,
                            clipboardID: clip.id,
                            record: nil
                        ))
                    }
                case .image:
                    let cgImage = store.loadClipboardImage(clip)
                    if let cgImage {
                        let hash = ScreenshotStore.computeImageHash(cgImage)
                        if seenImageHashes.contains(hash) { continue }
                        seenImageHashes.insert(hash)
                        clipboardImages.append((cgImage.width, cgImage.height, clip.createdAt))
                    }

                    feed.append(FeedItem(
                        id: clip.id,
                        kind: .image(cgImage: cgImage, recordID: nil),
                        title: "复制的图片",
                        subtitle: cgImage != nil ? "\(cgImage!.width) × \(cgImage!.height)" : "图片",
                        sourceApp: clip.sourceApp ?? "剪贴板",
                        createdAt: clip.createdAt,
                        rawText: nil,
                        thumbnail: cgImage,
                        clipboardID: clip.id,
                        record: nil
                    ))
                }
            }
        }

        // 2. 读取文字收纳便签（若该文本未在最近剪贴板中出现，则收录并以 updatedAt 时间排序）
        if let notes = try? store.listTextNotes() {
            for note in notes {
                if seenTexts.contains(note.content) { continue }
                seenTexts.insert(note.content)

                feed.append(FeedItem(
                    id: note.id,
                    kind: .text(content: note.content),
                    title: note.content.replacingOccurrences(of: "\n", with: " "),
                    subtitle: "收纳便签 · \(note.content.count) 个字符",
                    sourceApp: note.sourceApp ?? "收纳",
                    createdAt: note.updatedAt,
                    rawText: note.content,
                    thumbnail: nil,
                    clipboardID: nil,
                    record: nil
                ))
            }
        }

        // 3. 读取本地截图记录（若为历史截图且未在剪贴板中展示，融合进来）
        if let records = try? store.list() {
            for record in records {
                // 旧版本会把截图同时写进剪贴板历史：同尺寸且时间接近的，视为同一条
                if clipboardImages.contains(where: {
                    $0.width == record.width
                        && $0.height == record.height
                        && abs($0.at.timeIntervalSince(record.capturedAt)) < 15
                }) { continue }

                let thumb = store.loadThumbnail(record)
                if let thumb {
                    let hash = ScreenshotStore.computeImageHash(thumb)
                    if seenImageHashes.contains(hash) { continue }
                    seenImageHashes.insert(hash)
                }

                feed.append(FeedItem(
                    id: record.id,
                    kind: .image(cgImage: thumb, recordID: record.id),
                    title: record.filename,
                    subtitle: "\(record.width) × \(record.height) · \(byteString(record.fileSize))",
                    sourceApp: (record.sourceApp?.isEmpty == false ? record.sourceApp : "截图"),
                    createdAt: record.capturedAt,
                    rawText: nil,
                    thumbnail: thumb,
                    clipboardID: nil,
                    record: record
                ))
            }
        }

        feed.sort { $0.createdAt > $1.createdAt }
        return FeedLoadResult(items: feed)
    }

    // MARK: - 交互操作

    private func copyItem(_ item: FeedItem) {
        switch item.kind {
        case .text(let content):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
            // 自己写剪贴板不算新内容，避免历史刷新导致卡片跳到最前
            ClipboardMonitor.shared.markSelfWrite()

        case .image(let cgImage, _):
            if let record = item.record {
                Task {
                    if let image = await ScreenshotStore.loadImageAsync(record) {
                        Self.copyImageToPasteboard(image)
                    }
                }
            } else if let cgImage {
                Self.copyImageToPasteboard(cgImage)
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

    private static func copyImageToPasteboard(_ cgImage: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        ClipboardMonitor.shared.markSelfWrite()
    }

    private func openFloatingPreview(_ cgImage: CGImage) {
        CaptureCoordinator.shared.pin(image: cgImage, isPreview: true)
        onDismiss()
    }

    nonisolated private static func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - 图片块

private struct ImmersiveImageTile: View {
    let item: SearchPanelView.FeedItem
    let image: CGImage?
    let height: CGFloat
    let isSelected: Bool
    let isCopied: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onCopy: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // 浅灰留白底：完整截图等比居中，不裁内容
                Color(red: 0.947, green: 0.953, blue: 0.965)

                if let image {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .scaledToFit()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Color.black.opacity(0.22))
                        Text("截图")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                if isCopied {
                    copiedOverlay
                        .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .lensoAnimation(LensoAnimations.snappy, value: isCopied, reduceMotion: reduceMotion)

            // 常驻信息行：来源应用 + 时间，放在图片下方，不遮挡画面
            HStack(spacing: 5) {
                SourceAppIcon(name: item.sourceApp, size: 12)
                Text(displayApp)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(timeText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color.white)
        }
        .frame(height: height)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? LensoColors.kleinBlueBright : Color.black.opacity(hovering ? 0.14 : 0.07),
                    lineWidth: isSelected ? 2 : 1
                )
                .lensoAnimation(LensoAnimations.hover, value: isSelected, reduceMotion: reduceMotion)
        )
        .overlay(alignment: .topTrailing) {
            // 悬停时右上角浮出「复制 / 预览」快捷操作
            if hovering {
                TileQuickActions(onCopy: onCopy, onOpen: onOpen)
                    .padding(6)
                    .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }
        }
        .shadow(color: .black.opacity(hovering ? 0.14 : 0.06), radius: hovering ? 12 : 5, y: hovering ? 5 : 2)
        .lensoAnimation(LensoAnimations.hover, value: hovering, reduceMotion: reduceMotion)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onCopy() }
        .onTapGesture { onSelect() }
        .help(item.title)
    }

    private var copiedOverlay: some View {
        ZStack {
            Color.white.opacity(0.86)
            VStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(LensoColors.kleinBlueBright)
                Text("已复制")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.65))
            }
        }
    }

    private var displayApp: String {
        guard let app = item.sourceApp, !app.isEmpty else { return "剪贴板" }
        return app
    }

    private var timeText: String {
        item.createdAt.formatted(date: .omitted, time: .standard)
    }
}

// MARK: - 文字块

private struct ImmersiveTextTile: View {
    let item: SearchPanelView.FeedItem
    let content: String
    let height: CGFloat
    let isSelected: Bool
    let isCopied: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onCopy: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content)
                .font(.system(size: 11.5))
                .lineSpacing(2.2)
                .foregroundStyle(Color.black.opacity(0.78))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Text(kindLabel)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(LensoColors.kleinBlue)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LensoColors.kleinBlueSoft)
                    )
                SourceAppIcon(name: item.sourceApp, size: 13)
                Text(displayApp)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(timeText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 11)
        .padding(.bottom, 10)
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? LensoColors.kleinBlueBright : Color.black.opacity(hovering ? 0.14 : 0.07),
                    lineWidth: isSelected ? 2 : 1
                )
                .lensoAnimation(LensoAnimations.hover, value: isSelected, reduceMotion: reduceMotion)
        )
        .overlay(alignment: .topTrailing) {
            // 悬停时右上角浮出「复制 / 预览」快捷操作
            if hovering {
                TileQuickActions(onCopy: onCopy, onOpen: onOpen)
                    .padding(6)
                    .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }
        }
        .overlay {
            if isCopied {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                    VStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                        Text("已复制")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.65))
                    }
                }
                .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }
        }
        .lensoAnimation(LensoAnimations.snappy, value: isCopied, reduceMotion: reduceMotion)
        .shadow(color: .black.opacity(hovering ? 0.14 : 0.06), radius: hovering ? 12 : 5, y: hovering ? 5 : 2)
        .lensoAnimation(LensoAnimations.hover, value: hovering, reduceMotion: reduceMotion)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onCopy() }
        .onTapGesture { onSelect() }
        .help(content)
    }

    private var kindLabel: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("SELECT ") || trimmed.contains("{") && trimmed.contains(";") {
            return "代码"
        }
        return "文字"
    }

    private var displayApp: String {
        guard let app = item.sourceApp, !app.isEmpty else { return "剪贴板" }
        return app
    }

    private var timeText: String {
        item.createdAt.formatted(date: .omitted, time: .standard)
    }
}

// MARK: - 悬停快捷操作

/// 卡片右上角的「复制 / 预览」小胶囊：白底不透明，任何画面上都清晰可点
private struct TileQuickActions: View {
    let onCopy: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.62))
                    .frame(width: 27, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LensoPressButtonStyle())
            .help("复制 (↵)")

            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(width: 1, height: 12)

            Button(action: onOpen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.62))
                    .frame(width: 27, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LensoPressButtonStyle())
            .help("预览 (space)")
        }
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
    }
}

// MARK: - 顶部拖动带

/// 顶部留白处的透明拖动条：按住即可移动搜索窗口，光标显示为抓手
private struct SearchPanelDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            // 交给系统处理窗口拖动，位置会随窗口移动，关闭时记忆
            window?.performDrag(with: event)
        }
    }
}
