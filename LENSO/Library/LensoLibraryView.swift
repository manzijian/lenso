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
    @State private var section: Section = .screenshots
    @State private var viewMode: ViewMode = .grid
    @State private var searchText: String = ""
    @State private var timeFilter: TimeFilter = .all
    @State private var recordToDelete: ScreenshotRecord? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var showBatchDeleteConfirm: Bool = false

    @Environment(\.openWindow) private var openWindow

    enum Section { case screenshots, text, recent, favorites, analytics }
    enum ViewMode { case grid, list }
    enum TimeFilter: String, CaseIterable {
        case all = "全部时间"
        case today = "今天"
        case pastWeek = "近 7 天"
        case pastMonth = "近 30 天"
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 185, maximum: 265), spacing: 14)
    ]

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
                    feedHeader(title: "最近", subtitle: "过去 7 天的内容")
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
                        emptyIcon: "star"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    feedFooter(summary: favoriteSummary)

                case .analytics:
                    AnalyticsDashboardView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(mainBackground)
        }
        .frame(minWidth: 840, minHeight: 560)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: .openAnalyticsSection)) { _ in
            section = .analytics
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

    // MARK: - 侧边栏（无回收站，克莱因蓝激活胶囊）

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 顶部留出 macOS 红绿灯高度
            Color.clear.frame(height: 38)

            navigationItem(
                "全部截图",
                icon: "photo.stack.fill",
                count: images.count,
                isActive: section == .screenshots
            )
            .onTapGesture { section = .screenshots }

            navigationItem(
                "文字收纳",
                icon: "text.alignleft",
                count: notes.count,
                isActive: section == .text
            )
            .onTapGesture { section = .text }

            navigationItem(
                "最近",
                icon: "clock.fill",
                count: recentEntries.count,
                isActive: section == .recent
            )
            .onTapGesture { section = .recent }

            navigationItem(
                "收藏夹",
                icon: "star.fill",
                count: favoriteEntries.count,
                isActive: section == .favorites
            )
            .onTapGesture { section = .favorites }

            navigationItem(
                "数据看板",
                icon: "chart.bar.xaxis",
                isActive: section == .analytics
            )
            .onTapGesture { section = .analytics }

            Spacer()

            // 侧栏底部：偏好设置
            navigationItem(
                "偏好设置",
                icon: "gearshape.fill",
                isActive: false
            )
            .onTapGesture {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(width: 185)
    }

    private func navigationItem(
        _ title: String,
        icon: String,
        count: Int? = nil,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .white : Color(red: 0.18, green: 0.18, blue: 0.22))
                .frame(width: 18)

            Text(title)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .white : Color(red: 0.18, green: 0.18, blue: 0.22))

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: isActive ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isActive ? LensoColors.kleinBlueBright : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule().fill(isActive ? Color.white : Color.black.opacity(0.04))
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LensoColors.kleinBlueBright)
                    .shadow(color: LensoColors.kleinBlueBright.opacity(0.28), radius: 6, y: 2)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - 顶部工具栏（克莱因蓝强调色 + 搜索框 + 视图切换）

    private var topToolbar: some View {
        HStack(spacing: 12) {
            // 网格 / 列表视图切换器
            HStack(spacing: 2) {
                Button {
                    viewMode = .grid
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(viewMode == .grid ? LensoColors.kleinBlueBright : Color.secondary)
                        .frame(width: 28, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewMode == .grid ? Color.white : Color.clear)
                                .shadow(color: Color.black.opacity(viewMode == .grid ? 0.08 : 0), radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    viewMode = .list
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(viewMode == .list ? LensoColors.kleinBlueBright : Color.secondary)
                        .frame(width: 28, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewMode == .list ? Color.white : Color.clear)
                                .shadow(color: Color.black.opacity(viewMode == .list ? 0.08 : 0), radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.04)))

            // 时间范围筛选
            Menu {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    Button {
                        timeFilter = filter
                    } label: {
                        HStack {
                            Text(filter.rawValue)
                            if timeFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(timeFilter.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
                )
            }
            .menuStyle(.borderlessButton)

            Spacer()

            // 搜索输入框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(searchText.isEmpty ? Color.secondary : LensoColors.kleinBlueBright)

                TextField("搜索截图文件名...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 170)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white)
                    .overlay(
                        Capsule()
                            .stroke(searchText.isEmpty ? Color.black.opacity(0.08) : LensoColors.kleinBlueBright, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
            )

            // 全局 Spotlight 搜索入口
            Button {
                SearchPanelController.shared.show()
            } label: {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white).overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1)))
            }
            .buttonStyle(.plain)
            .help("呼出全局搜索 (⇧⌘F)")
        }
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

    // MARK: - 截图网格视图（纯白 Apple 卡片 + 克莱因蓝选中）

    private var screenshotGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(filteredImages) { item in
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
            .padding(.bottom, 20)
        }
    }

    // MARK: - 列表视图

    private var screenshotListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredImages) { item in
                    let record = recordsByID[item.id]
                    screenshotListRow(item: item, record: record)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func screenshotListRow(item: LibraryImage, record: ScreenshotRecord?) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return HStack(spacing: 12) {
            Image(nsImage: item.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(record?.filename ?? "Screenshot")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let record {
                    Text("\(record.width) × \(record.height) · \(record.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            FavoriteStarButton(isFavorite: item.isFavorite) {
                toggleFavorite(item)
            }

            Button {
                copyImage(item)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("复制图片")

            Button {
                if let record {
                    recordToDelete = record
                    showDeleteConfirm = true
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("直接删除")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? LensoColors.kleinBlueBright : Color.black.opacity(0.06), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpenPreview?(item.id)
        }
        .onTapGesture(count: 1) {
            toggleSelection(item.id)
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 38))
                .foregroundStyle(LensoColors.kleinBlueBright.opacity(0.5))
            Text(searchText.isEmpty ? "图库空空如也" : "未找到匹配截图")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.8))
            Text(searchText.isEmpty ? "按 ⇧⌘1 截取一张屏幕画面，或在菜单栏直接截图" : "请尝试更换关键词搜索")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部栏与批量直接删除操作

    private var footer: some View {
        HStack(spacing: 12) {
            if selectedIDs.isEmpty {
                Text("\(filteredImages.count) 张截图 · 全部保存在本地磁盘")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Text("已选择 \(selectedIDs.count) 张")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LensoColors.kleinBlueBright)

                    Text("·")
                        .foregroundStyle(.secondary)

                    Button("全选") {
                        selectedIDs = Set(filteredImages.map(\.id))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LensoColors.kleinBlueBright)

                    Button("取消选择") {
                        selectedIDs.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !selectedIDs.isEmpty {
                // 批量直接删除按钮（直接彻底删除，无回收站）
                Button {
                    showBatchDeleteConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("直接删除 (\(selectedIDs.count))")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red))
                }
                .buttonStyle(.plain)
                .help("直接彻底从磁盘清除所选项")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - 数据操作（直接彻底删除）

    private func toggleSelection(_ id: UUID) {
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .onTapGesture { SearchPanelController.shared.show() }
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

// MARK: - 网格图片单元（纯白高质感 Apple 卡片 + 克莱因蓝选中）

private struct LibraryImageCell: View {
    let item: LibraryImage
    let record: ScreenshotRecord?
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggleSelection: () -> Void
    let onToggleFavorite: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                Image(nsImage: item.thumbnail)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                // 边框处理：选中为高亮克莱因蓝，未选中为苹果质感浅灰细边
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(LensoColors.kleinBlueBright, lineWidth: 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(LensoColors.kleinBlueSoft)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                }
            }
            // 右上角选中标记（克莱因蓝圆形徽章）
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Circle()
                        .fill(LensoColors.kleinBlueBright)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: LensoColors.kleinBlueBright.opacity(0.3), radius: 3, y: 1)
                        .padding(7)
                }
            }
            // 左上角收藏星标
            .overlay(alignment: .topLeading) {
                FavoriteStarButton(isFavorite: item.isFavorite, action: onToggleFavorite)
                    .opacity(hovering || item.isFavorite ? 1 : 0)
                    .allowsHitTesting(hovering || item.isFavorite)
                    .padding(6)
            }
            // 左下角尺寸徽标
            .overlay(alignment: .bottomLeading) {
                if let record {
                    Text("\(record.width) × \(record.height)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .opacity(hovering ? 1 : 0.85)
                        .padding(6)
                }
            }
            // 右下角悬停操作栏（预览、复制、直接删除）
            .overlay(alignment: .bottomTrailing) {
                if hovering {
                    HStack(spacing: 4) {
                        Button(action: onOpen) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.primary.opacity(0.8))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.white))
                        }
                        .buttonStyle(.plain)
                        .help("双击打开预览")

                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.primary.opacity(0.8))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.white))
                        }
                        .buttonStyle(.plain)
                        .help("复制到剪贴板")

                        Button(action: onDelete) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.red)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.white))
                        }
                        .buttonStyle(.plain)
                        .help("直接彻底删除")
                    }
                    .padding(4)
                    .background(Capsule().fill(Color.black.opacity(0.25)))
                    .padding(6)
                }
            }
            .shadow(color: Color.black.opacity(isSelected ? 0.12 : (hovering ? 0.08 : 0.04)), radius: hovering ? 8 : 4, y: hovering ? 4 : 2)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .contextMenu {
                Button("打开预览", action: onOpen)
                Button("复制到剪贴板", action: onCopy)
                Button(item.isFavorite ? "取消收藏" : "收藏", action: onToggleFavorite)
                Divider()
                Button("直接删除 (不可撤销)", role: .destructive, action: onDelete)
            }
            .onTapGesture(count: 2) {
                onOpen()
            }
            .onTapGesture(count: 1) {
                onToggleSelection()
            }
            .help("双击打开贴图预览，单击选中")
    }
}
