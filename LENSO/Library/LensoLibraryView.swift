import SwiftUI

/// 图库视图 — 严格按参考图 4：
/// 侧栏（带计数徽章）+ 胶囊工具栏（全部时间 ▾）+ 网格（选中蓝框+勾角标）+ 底部合计与分享/删除
struct LensoLibraryView: View {
    let images: [LibraryImage]
    @State private var selectedIDs: Set<UUID> = []
    @State private var searchText = ""
    var onOpenPreview: ((UUID) -> Void)? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 145), spacing: 12)
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(spacing: 12) {
                toolbar

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(images) { item in
                            imageCell(item)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }

                footer
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(
            cornerRadius: 20,
            style: .continuous
        ))
    }

    // MARK: - 侧栏（带计数）

    private let navCounts: [String: Int] = [
        "最近": 24, "收藏": 18, "回收站": 12,
        "工作": 32, "生活": 28, "设计": 24, "其他": 44,
    ]

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            navigationItem("全部截图", icon: "folder.fill", count: images.count, isPrimary: true)
            navigationItem("最近", icon: "clock")
            navigationItem("收藏", icon: "star")
            navigationItem("回收站", icon: "trash")

            Divider().padding(.vertical, 8)

            Text("标签")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            tagItem("工作", color: .yellow)
            tagItem("生活", color: .green)
            tagItem("设计", color: .orange)
            tagItem("其他", color: .gray)

            Spacer()

            navigationItem("设置", icon: "gearshape")
        }
        .padding(12)
        .frame(width: LensoStyle.sidebarWidth)
    }

    private func navigationItem(
        _ title: String,
        icon: String,
        count: Int? = nil,
        isPrimary: Bool = false
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if isPrimary {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.14))
            }
        }
        .contentShape(Rectangle())
    }

    private func tagItem(_ title: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            if let count = navCounts[title] {
                Text("\(count)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - 工具栏（胶囊分段）

    private var toolbar: some View {
        HStack(spacing: 10) {
            // 网格/列表分段
            HStack(spacing: 2) {
                Image(systemName: "square.grid.2x2")
                    .frame(width: 30, height: 26)
                    .background(Capsule().fill(.primary.opacity(0.07)))
                Image(systemName: "list.bullet")
                    .frame(width: 30, height: 26)
            }

            // 全部时间 ▾
            HStack(spacing: 4) {
                Text("全部时间").font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(.primary.opacity(0.07)))
            .contentShape(Rectangle())

            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(Capsule().fill(.background.opacity(0.65)))
        .overlay(Capsule().stroke(.separator.opacity(0.35), lineWidth: 1))
    }

    // MARK: - 图片单元（选中蓝框 + 勾角标）

    private func imageCell(_ item: LibraryImage) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return Button {
            if isSelected {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
        } label: {
            Image(nsImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if isSelected {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.blue, lineWidth: 2.5)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, Color.blue)
                                .padding(7)
                        }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) {
            onOpenPreview?(item.id)
        }
    }

    // MARK: - 底部（合计 + 操作）

    private var footer: some View {
        HStack {
            if selectedIDs.isEmpty {
                Text("\(images.count) 张截图")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("已选择 \(selectedIDs.count) 张 · \(totalSelectedSize)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14))
                .foregroundStyle(selectedIDs.isEmpty ? Color.secondary.opacity(0.4) : .primary)
            Image(systemName: "trash")
                .font(.system(size: 14))
                .foregroundStyle(selectedIDs.isEmpty ? Color.secondary.opacity(0.4) : .red)
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var totalSelectedSize: String {
        // MVP：按选中数估算（真实大小接入后替换）
        let mb = Double(selectedIDs.count) * 2.3
        return String(format: "%.1f MB", mb)
    }
}
