import SwiftUI
import AppKit

// MARK: - 顶部工具栏

struct LibraryTopToolbarView: View {
    @Binding var viewMode: LensoLibraryView.ViewMode
    @Binding var timeFilter: LensoLibraryView.TimeFilter
    @Binding var searchText: String

    var body: some View {
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
}

// MARK: - 底部操作栏

struct LibraryFooterView: View {
    let totalCount: Int
    @Binding var selectedIDs: Set<UUID>
    let allIDs: [UUID]
    let onBatchDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if selectedIDs.isEmpty {
                Text("\(totalCount) 张截图 · 全部保存在本地磁盘")
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
                        selectedIDs = Set(allIDs)
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
                Button(action: onBatchDelete) {
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
                    Text("\(record.width) × \(record.height) · \(record.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            FavoriteStarButton(isFavorite: item.isFavorite) {
                onToggleFavorite()
            }

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("复制图片")

            Button(action: onDelete) {
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

    var body: some View {
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
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
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
