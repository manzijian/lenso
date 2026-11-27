import SwiftUI
import AppKit

// MARK: - 顶部工具栏

struct LibraryTopToolbarView: View {
    @Binding var viewMode: LensoLibraryView.ViewMode
    @Binding var timeFilter: LensoLibraryView.TimeFilter
    @Binding var searchText: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var viewModeNamespace

    var body: some View {
        HStack(spacing: 12) {
            // 网格 / 列表视图切换器
            HStack(spacing: 2) {
                Button {
                    LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                        viewMode = .grid
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(viewMode == .grid ? LensoColors.kleinBlueBright : Color.secondary)
                        .frame(width: 28, height: 26)
                        .background {
                            if viewMode == .grid {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "viewModePill", in: viewModeNamespace)
                            }
                        }
                }
                .buttonStyle(LensoPressButtonStyle())

                Button {
                    LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                        viewMode = .list
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(viewMode == .list ? LensoColors.kleinBlueBright : Color.secondary)
                        .frame(width: 28, height: 26)
                        .background {
                            if viewMode == .list {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "viewModePill", in: viewModeNamespace)
                            }
                        }
                }
                .buttonStyle(LensoPressButtonStyle())
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            // 时间范围筛选
            Menu {
                ForEach(LensoLibraryView.TimeFilter.allCases, id: \.self) { filter in
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
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
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
                    .buttonStyle(LensoPressButtonStyle())
                    .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                }
            }
            .lensoAnimation(LensoAnimations.snappy, value: searchText.isEmpty, reduceMotion: reduceMotion)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        Capsule()
                            .stroke(searchText.isEmpty ? Color.primary.opacity(0.08) : LensoColors.kleinBlueBright, lineWidth: 1)
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
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor)).overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1)))
            }
            .buttonStyle(LensoPressButtonStyle())
            .help("呼出全局搜索 (⇧⌘F)")
        }
    }
}

// MARK: - 底部操作栏

struct LibraryFooterView: View {
    let totalCount: Int
    @Binding var selectedIDs: Set<UUID>
    let allIDs: [UUID]
    let onBatchDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            if selectedIDs.isEmpty {
                Text("\(totalCount) 张截图 · 全部保存在本地磁盘")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lensoNumericTransition()
            } else {
                HStack(spacing: 8) {
                    Text("已选择 \(selectedIDs.count) 张")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .monospacedDigit()
                        .lensoNumericTransition()

                    Text("·")
                        .foregroundStyle(.secondary)

                    Button("全选") {
                        selectedIDs = Set(allIDs)
                    }
                    .buttonStyle(LensoPressButtonStyle())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LensoColors.kleinBlueBright)

                    Button("取消选择") {
                        selectedIDs.removeAll()
                    }
                    .buttonStyle(LensoPressButtonStyle())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .transition(LensoTransitions.bottomExpand(reduceMotion: reduceMotion))
            }

            Spacer()

            if !selectedIDs.isEmpty {
                Button(action: onBatchDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("直接删除 (\(selectedIDs.count))")
                            .monospacedDigit()
                            .lensoNumericTransition()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red))
                }
                .buttonStyle(LensoPressButtonStyle())
                .transition(LensoTransitions.bottomExpand(reduceMotion: reduceMotion))
                .help("直接彻底从磁盘清除所选项")
            }
        }
        .lensoAnimation(LensoAnimations.snappy, value: selectedIDs.isEmpty, reduceMotion: reduceMotion)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - 列表视图行

struct LibraryScreenshotListRow: View {
    let item: LibraryImage
    let record: ScreenshotRecord?
    let isSelected: Bool
    let onToggleFavorite: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onOpenPreview: () -> Void
    let onToggleSelection: () -> Void

    @State private var isCopied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
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
                    Text("\(record.sourceApp ?? "截图") · \(record.capturedAt.lensoRelativeDayTime) · \(record.width) × \(record.height)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer()

            FavoriteStarButton(isFavorite: item.isFavorite) {
                onToggleFavorite()
            }

            Button {
                onCopy()
                LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                    isCopied = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    await MainActor.run {
                        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                            isCopied = false
                        }
                    }
                }
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: isCopied ? .bold : .regular))
                    .foregroundStyle(isCopied ? Color(red: 0.11, green: 0.55, blue: 0.33) : .secondary)
                    .lensoSymbolReplace()
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(LensoPressButtonStyle())
            .help("复制图片")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(LensoPressButtonStyle())
            .help("直接删除")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? LensoColors.kleinBlueBright : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)
        )
        .lensoAnimation(LensoAnimations.snappy, value: isSelected, reduceMotion: reduceMotion)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpenPreview()
        }
        .onTapGesture(count: 1) {
            onToggleSelection()
        }
    }
}

// MARK: - 空状态

struct LibraryEmptyStateView: View {
    let searchText: String
    var timeFilter: LensoLibraryView.TimeFilter = .all
    var onResetTimeFilter: (() -> Void)? = nil

    private var titleText: String {
        if !searchText.isEmpty { return "未找到匹配截图" }
        if timeFilter != .all { return "该时间段内暂无截图" }
        return "图库空空如也"
    }

    private var subtitleText: String {
        if !searchText.isEmpty { return "请尝试更换关键词搜索" }
        if timeFilter != .all { return "当前筛选范围：\(timeFilter.rawValue)" }
        return "按 ⇧⌘1 截取一张屏幕画面，或在菜单栏直接截图"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: timeFilter != .all && searchText.isEmpty ? "calendar.badge.exclamationmark" : "photo.on.rectangle.angled")
                .font(.system(size: 38))
                .foregroundStyle(LensoColors.kleinBlueBright.opacity(0.5))
            Text(titleText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.8))
            Text(subtitleText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if timeFilter != .all && searchText.isEmpty, let onResetTimeFilter {
                Button(action: onResetTimeFilter) {
                    Text("查看全部")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(LensoColors.kleinBlueBright))
                }
                .buttonStyle(LensoPressButtonStyle())
                .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Feed 页头与页脚

struct LibraryFeedSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.primary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

struct LibraryFeedSectionFooter: View {
    let summary: String

    var body: some View {
        HStack {
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - 网格图片单元（纯白高质感 Apple 卡片 + 克莱因蓝选中）

struct LibraryImageCell: View {
    let item: LibraryImage
    let record: ScreenshotRecord?
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggleSelection: () -> Void
    let onToggleFavorite: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var isCopied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 截图卡片上的精确时间（时:分:秒）
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

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
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(LensoColors.kleinBlueBright, lineWidth: 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(LensoColors.kleinBlueSoft)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
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
                        .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                }
            }
            .overlay(alignment: .topLeading) {
                FavoriteStarButton(isFavorite: item.isFavorite, action: onToggleFavorite)
                    .opacity(hovering || item.isFavorite ? 1 : 0)
                    .allowsHitTesting(hovering || item.isFavorite)
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                if let record {
                    Text("\(Self.clockFormatter.string(from: record.capturedAt)) · \(record.sourceApp ?? "截图")")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .opacity(hovering ? 1 : 0.9)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if hovering {
                    HStack(spacing: 4) {
                        Button(action: onOpen) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.primary.opacity(0.88))
                                .frame(width: 22, height: 22)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(LensoPressButtonStyle())
                        .help("双击打开预览")

                        Button {
                            onCopy()
                            LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                                isCopied = true
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(1.2))
                                await MainActor.run {
                                    LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                                        isCopied = false
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc.fill")
                                .font(.system(size: 10, weight: isCopied ? .bold : .regular))
                                .foregroundStyle(isCopied ? Color(red: 0.11, green: 0.55, blue: 0.33) : Color.primary.opacity(0.88))
                                .lensoSymbolReplace()
                                .frame(width: 22, height: 22)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(LensoPressButtonStyle())
                        .help("复制到剪贴板")

                        Button(action: onDelete) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.red)
                                .frame(width: 22, height: 22)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(LensoPressButtonStyle())
                        .help("直接彻底删除")
                    }
                    .padding(4)
                    .background(Capsule().fill(Color.black.opacity(0.28)))
                    .padding(6)
                    .transition(.opacity)
                }
            }
            .shadow(color: Color.black.opacity(isSelected ? 0.12 : (hovering ? 0.08 : 0.04)), radius: hovering ? 8 : 4, y: hovering ? 4 : 2)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .lensoAnimation(LensoAnimations.hover, value: hovering, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.snappy, value: isSelected, reduceMotion: reduceMotion)
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
