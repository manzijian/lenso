import SwiftUI
import AppKit

/// 图库视图 — Apple 设计风格 + 经典克莱因蓝（International Klein Blue）高对比白底搭配
/// 侧栏导航（彻底移除回收站）+ 顶部搜索过滤条 + 卡片式网格/列表 + 悬停快捷栏 + 直接彻底删除
struct LensoLibraryView: View {
    let images: [LibraryImage]
    let records: [ScreenshotRecord]
    let notes: [TextNote]
    var onOpenPreview: ((UUID) -> Void)? = nil

    @State private var selectedIDs: Set<UUID> = []
    @State private var section: LibrarySection = .screenshots
    @State private var viewMode: ViewMode = .grid
    @State private var searchText: String = ""
    @State private var timeFilter: TimeFilter = .all
    @State private var recordToDelete: ScreenshotRecord? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var showBatchDeleteConfirm: Bool = false
    // 触控板双指缩放：按比例调整卡片大小与列数
    @State private var cardScale: CGFloat = 1.0
    @State private var gestureStartScale: CGFloat = 1.0
    @State private var gridContainerWidth: CGFloat = 680
    @FocusState private var gridFocused: Bool

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    typealias Section = LibrarySection
    enum ViewMode { case grid, list }
    enum TimeFilter: String, CaseIterable {
        case all = "全部时间"
        case today = "今天"
        case pastWeek = "近 7 天"
        case pastMonth = "近 30 天"
    }

    private var cardWidth: CGFloat { 200 * cardScale }

    private var currentGridColumnsCount: Int {
        max(1, Int((max(0, gridContainerWidth - 32) + 14) / (cardWidth + 14)))
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth + 2), spacing: 14)]
    }

    private var recordsByID: [UUID: ScreenshotRecord] {
        Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .background(sidebarBackground)

            VStack(spacing: 0) {
                switch section {
                case .screenshots:
                    topToolbar
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                    if filteredImages.isEmpty {
                        emptyStateView
                    } else {
                        if viewMode == .grid {
                            screenshotGrid
                        } else {
                            screenshotListView
                        }
                    }

                    footer
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                case .text:
                    TextNotesView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .recent:
                    feedHeader(title: "最近 7 天", subtitle: "过去 7 天新增的内容")
                    LibraryFeedView(
                        entries: recentEntries,
                        emptyTitle: "最近 7 天还没有内容",
                        emptyMessage: "截图和文字收纳条目会按时间出现在这里",
                        emptyIcon: "clock"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    feedFooter(summary: recentSummary)

                case .favorites:
                    feedHeader(title: "收藏", subtitle: "截图与文字")
                    LibraryFeedView(
                        entries: favoriteEntries,
                        emptyTitle: "还没有收藏",
                        emptyMessage: "点卡片上的星标即可收藏截图或文字",
                        emptyIcon: "star",
                        groupsByFavoriteDate: true
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    feedFooter(summary: favoriteSummary)

                case .analytics:
                    AnalyticsDashboardView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .settings(let category):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 8) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(LensoColors.kleinBlueBright)
                                Text(category.rawValue)
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundStyle(Color.primary)
                                Spacer()
                            }
                            .padding(.top, 4)

                            SettingsSectionContentView(category: category)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(mainBackground)
            .lensoAnimation(LensoAnimations.snappy, value: section, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.snappy, value: viewMode, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.snappy, value: timeFilter, reduceMotion: reduceMotion)
        }
        .frame(minWidth: 840, minHeight: 560)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onChange(of: filteredImages.map(\.id)) { visibleIDs in
            let validSet = Set(visibleIDs)
            let pruned = selectedIDs.intersection(validSet)
            if pruned != selectedIDs {
                selectedIDs = pruned
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAnalyticsSection)) { _ in
            section = .analytics
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsFromMenu)) { _ in
            section = .settings(.general)
        }
        .alert(
            "确定直接删除？",
            isPresented: $showDeleteConfirm,
            presenting: recordToDelete
        ) { record in
            Button("直接删除", role: .destructive) {
                executeDirectDelete(record)
            }
            Button("取消", role: .cancel) {}
        } message: { record in
            Text("已取消回收站机制。截图「\(record.filename)」将从本地磁盘中彻底永久清除，此操作不可撤销。")
        }
        .alert(
            "确定直接删除选中的 \(selectedIDs.count) 张截图？",
            isPresented: $showBatchDeleteConfirm
        ) {
            Button("直接彻底删除", role: .destructive) {
                executeBatchDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已取消回收站机制。选中的 \(selectedIDs.count) 个文件将从本地磁盘中彻底永久清除，此操作不可撤销。")
        }
        .lensoColorScheme()
    }

    // MARK: - 背景设计（Apple 原生纯白高雅质感 + 克莱因蓝微光）

    private var mainBackground: some View {
        ZStack {
            Color(red: 0.985, green: 0.988, blue: 0.995)
            // 右上角微弱克莱因蓝光斑（仅 3% 透明度，烘托科技感与艺术感）
            RadialGradient(
                colors: [LensoColors.kleinBlueBright.opacity(0.045), .clear],
                center: UnitPoint(x: 0.9, y: 0.05),
                startRadius: 0,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }

    private var sidebarBackground: some View {
        Color.white
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.black.opacity(0.07)).frame(width: 1)
            }
            .ignoresSafeArea()
    }

    // MARK: - 侧边栏（无回收站，克莱因蓝激活胶囊，看板下方铺开设置二级菜单）

    private var sidebar: some View {
        LibrarySidebarView(
            section: $section,
            screenshotsCount: images.count,
            textCount: notes.count,
            recentCount: recentEntries.count,
            favoritesCount: favoriteEntries.count,
            storageBytes: records.reduce(Int64(0)) { $0 + Int64($1.fileSize) }
        )
    }

    // MARK: - 顶部工具栏（克莱因蓝强调色 + 搜索框 + 视图切换）

    private var topToolbar: some View {
        LibraryTopToolbarView(viewMode: $viewMode, timeFilter: $timeFilter, searchText: $searchText)
    }

    // MARK: - 筛选数据

    private var filteredImages: [LibraryImage] {
        let base = images.filter { item in
            guard let record = recordsByID[item.id] else { return true }
            // 时间过滤
            if !matchesTimeFilter(record.capturedAt) { return false }
            // 搜索过滤
            if !searchText.isEmpty {
                return record.filename.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
        return base
    }

    private func matchesTimeFilter(_ date: Date) -> Bool {
        let now = Date()
        let cal = Calendar.current
        switch timeFilter {
        case .all: return true
        case .today: return cal.isDateInToday(date)
        case .pastWeek:
            guard let limit = cal.date(byAdding: .day, value: -7, to: now) else { return true }
            return date >= limit
        case .pastMonth:
            guard let limit = cal.date(byAdding: .day, value: -30, to: now) else { return true }
            return date >= limit
        }
    }

    // MARK: - 截图网格视图（按日期分组的白底卡片 + 克莱因蓝选中）

    private var screenshotGrid: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedImages) { group in
                    SwiftUI.Section {
                        LazyVGrid(columns: gridColumns, spacing: 14) {
                            ForEach(group.items) { item in
                                let record = recordsByID[item.id]
                                LibraryImageCell(
                                    item: item,
                                    record: record,
                                    isSelected: selectedIDs.contains(item.id),
                                    onOpen: { onOpenPreview?(item.id) },
                                    onToggleSelection: { toggleSelection(item.id) },
                                    onToggleFavorite: { toggleFavorite(item) },
                                    onCopy: { copyImage(item) },
                                    onDelete: {
                                        if let record {
                                            recordToDelete = record
                                            showDeleteConfirm = true
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    } header: {
                        LibraryDayHeader(title: group.title, count: group.items.count)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { gridContainerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { gridContainerWidth = $0 }
            }
        )
        .simultaneousGesture(magnifyGesture)
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .onAppear { gridFocused = true }
        .onKeyPress(.leftArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.rightArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(by: -currentGridColumnsCount); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: currentGridColumnsCount); return .handled }
        .onKeyPress(.space) { openSelection(); return .handled }
        .onKeyPress(.delete) { requestDeleteSelection(); return .handled }
        .onKeyPress(phases: .down) { press in
            if press.modifiers.contains(.command) {
                switch press.characters.lowercased() {
                case "a":
                    selectedIDs = Set(filteredImages.map(\.id))
                    return .handled
                case "c":
                    if !selectedIDs.isEmpty {
                        copySelectedImages()
                        return .handled
                    }
                default:
                    break
                }
            }
            return .ignored
        }
    }

    // MARK: - 键盘操作

    private func moveSelection(by offset: Int) {
        let items = filteredImages
        guard !items.isEmpty else { return }
        gridFocused = true

        let current = items.firstIndex { selectedIDs.contains($0.id) }
        let base = current ?? (offset > 0 ? -1 : 0)
        let next = min(max(base + offset, 0), items.count - 1)
        selectedIDs = [items[next].id]
    }

    private func openSelection() {
        guard let id = selectedIDs.first else { return }
        onOpenPreview?(id)
    }

    private func requestDeleteSelection() {
        if selectedIDs.count > 1 {
            showBatchDeleteConfirm = true
        } else if let id = selectedIDs.first, let record = recordsByID[id] {
            recordToDelete = record
            showDeleteConfirm = true
        }
    }

    /// 双指捏合：0.75× ~ 1.6×，按 0.04 档位吸附
    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let target = gestureStartScale * value.magnification
                let clamped = min(max(target, 0.75), 1.6)
                let snapped = (clamped / 0.04).rounded() * 0.04
                if abs(snapped - cardScale) > 0.001 {
                    cardScale = snapped
                }
            }
            .onEnded { _ in
                gestureStartScale = cardScale
            }
    }

    // MARK: - 日期分组

    private struct DayGroup: Identifiable {
        let id: Date
        let title: String
        let items: [LibraryImage]
    }

    private var groupedImages: [DayGroup] {
        let calendar = Calendar.current
        var buckets: [Date: [LibraryImage]] = [:]
        for item in filteredImages {
            let date = recordsByID[item.id]?.capturedAt ?? Date()
            let day = calendar.startOfDay(for: date)
            buckets[day, default: []].append(item)
        }
        return buckets.keys.sorted(by: >).map { day in
            DayGroup(id: day, title: LibraryDayLabel.title(for: day), items: buckets[day] ?? [])
        }
    }

    // MARK: - 列表视图

    private var screenshotListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredImages) { item in
                    let record = recordsByID[item.id]
                    LibraryScreenshotListRow(
                        item: item,
                        record: record,
                        isSelected: selectedIDs.contains(item.id),
                        onToggleFavorite: { toggleFavorite(item) },
                        onCopy: { copyImage(item) },
                        onDelete: {
                            if let record {
                                recordToDelete = record
                                showDeleteConfirm = true
                            }
                        },
                        onOpenPreview: { onOpenPreview?(item.id) },
                        onToggleSelection: { toggleSelection(item.id) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .onAppear { gridFocused = true }
        .onKeyPress(.leftArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.rightArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.space) { openSelection(); return .handled }
        .onKeyPress(.delete) { requestDeleteSelection(); return .handled }
        .onKeyPress(phases: .down) { press in
            if press.modifiers.contains(.command) {
                switch press.characters.lowercased() {
                case "a":
                    selectedIDs = Set(filteredImages.map(\.id))
                    return .handled
                case "c":
                    if !selectedIDs.isEmpty {
                        copySelectedImages()
                        return .handled
                    }
                default:
                    break
                }
            }
            return .ignored
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        LibraryEmptyStateView(
            searchText: searchText,
            timeFilter: timeFilter,
            onResetTimeFilter: {
                LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                    timeFilter = .all
                }
            }
        )
    }

    // MARK: - 底部栏与批量直接删除操作

    private var footer: some View {
        LibraryFooterView(
            totalCount: filteredImages.count,
            selectedIDs: $selectedIDs,
            allIDs: filteredImages.map(\.id),
            onBatchDelete: { showBatchDeleteConfirm = true }
        )
    }

    // MARK: - 数据操作（直接彻底删除）

    private func toggleSelection(_ id: UUID) {
        gridFocused = true
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func toggleFavorite(_ item: LibraryImage) {
        try? ScreenshotStore.shared.setScreenshotFavorite(!item.isFavorite, id: item.id)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }

    private func copyImage(_ item: LibraryImage) {
        guard let record = recordsByID[item.id],
              let image = ScreenshotStore.shared.loadImage(record) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        SaveToastController.shared.show(title: "已复制到剪贴板", subtitle: record.filename, thumbnail: image)
    }

    private func copySelectedImages() {
        let selectedItems = filteredImages.filter { selectedIDs.contains($0.id) }
        guard !selectedItems.isEmpty else { return }
        if selectedItems.count == 1 {
            copyImage(selectedItems[0])
            return
        }
        let nsImages = selectedItems.compactMap { item -> NSImage? in
            guard let record = recordsByID[item.id],
                  let cg = ScreenshotStore.shared.loadImage(record) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        guard !nsImages.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(nsImages)
        SaveToastController.shared.show(title: "已复制 \(nsImages.count) 张截图", subtitle: "已写入剪贴板", thumbnail: nil)
    }

    /// 单项直接彻底删除（无回收站）
    private func executeDirectDelete(_ record: ScreenshotRecord) {
        try? ScreenshotStore.shared.delete(record)
        selectedIDs.remove(record.id)
        recordToDelete = nil
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
        SaveToastController.shared.show(title: "已直接删除", subtitle: "文件已从本地磁盘彻底清除", thumbnail: nil)
    }

    /// 批量直接彻底删除（无回收站）
    private func executeBatchDelete() {
        let store = ScreenshotStore.shared
        for id in selectedIDs {
            if let record = recordsByID[id] {
                try? store.delete(record)
            }
        }
        let count = selectedIDs.count
        selectedIDs.removeAll()
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
        SaveToastController.shared.show(title: "已批量删除", subtitle: "共 \(count) 项已彻底从磁盘清除", thumbnail: nil)
    }

    // MARK: - 最近 / 收藏处理

    private var recentCutoff: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
    }

    private var thumbnailByID: [UUID: NSImage] {
        Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0.thumbnail) })
    }

    private var recentEntries: [LibraryEntry] {
        let cutoff = recentCutoff
        let screenshotEntries = records
            .filter { $0.capturedAt >= cutoff }
            .map { LibraryEntry.screenshot($0, thumbnail: thumbnailByID[$0.id]) }
        let noteEntries = notes
            .filter { $0.updatedAt >= cutoff }
            .map { LibraryEntry.note($0) }
        return (screenshotEntries + noteEntries).sorted { $0.date > $1.date }
    }

    private var favoriteEntries: [LibraryEntry] {
        let screenshotEntries = records
            .filter(\.isFavorite)
            .map { LibraryEntry.screenshot($0, thumbnail: thumbnailByID[$0.id]) }
        let noteEntries = notes
            .filter(\.isFavorite)
            .map { LibraryEntry.note($0) }
        return (screenshotEntries + noteEntries).sorted {
            ($0.favoriteDate ?? $0.date) > ($1.favoriteDate ?? $1.date)
        }
    }

    private var recentSummary: String {
        let scCount = recentEntries.filter { $0.kind == .screenshot }.count
        let noteCount = recentEntries.filter { $0.kind == .note }.count
        return "近 7 天 · \(scCount) 张截图 · \(noteCount) 条文字"
    }

    private var favoriteSummary: String {
        let scCount = favoriteEntries.filter { $0.kind == .screenshot }.count
        let noteCount = favoriteEntries.filter { $0.kind == .note }.count
        return "已收藏 \(scCount) 张截图 · \(noteCount) 条文字"
    }

    private func feedHeader(title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.8))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
        }
    }

    private func feedFooter(summary: String) -> some View {
        HStack {
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
