import SwiftUI

/// 图库视图 — 侧栏导航 + 网格 + 工具栏 + 底部操作条（按 LensoStyle 视觉规范）
struct LensoLibraryView: View {
    let images: [LibraryImage]
    @State private var selectedIDs: Set<UUID> = []
    @State private var searchText = ""

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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            navigationItem("全部截图", icon: "folder.fill")
            navigationItem("最近", icon: "clock")
            navigationItem("收藏", icon: "star")
            navigationItem("回收站", icon: "trash")

            Divider().padding(.vertical, 8)

            Text("标签")
                .font(.caption)
                .foregroundStyle(.secondary)

            navigationItem("工作", icon: "circle.fill")
            navigationItem("生活", icon: "circle.fill")
            navigationItem("设计", icon: "circle.fill")

            Spacer()

            navigationItem("设置", icon: "gearshape")
        }
        .padding(12)
        .frame(width: LensoStyle.sidebarWidth)
    }

    private func navigationItem(
        _ title: String,
        icon: String
    ) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if title == "全部截图" {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.blue.opacity(0.13))
                }
            }
    }

    private var toolbar: some View {
        HStack {
            Image(systemName: "square.grid.2x2")
            Image(systemName: "list.bullet")

            Divider().frame(height: 20)

            Text("全部时间")
                .font(.system(size: 12))

            Spacer()

            Image(systemName: "magnifyingglass")
            Image(systemName: "ellipsis")
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13))
    }

    private func imageCell(_ item: LibraryImage) -> some View {
        Button {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                Text(item.sourceName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedIDs.contains(item.id)
                          ? Color.blue.opacity(0.12)
                          : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selectedIDs.contains(item.id)
                        ? Color.blue
                        : Color.clear,
                        lineWidth: 2
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text("已选择 \(selectedIDs.count) 张")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "square.and.arrow.up")
            Image(systemName: "trash")
            Image(systemName: "ellipsis")
        }
        .padding(.horizontal, 8)
    }
}
