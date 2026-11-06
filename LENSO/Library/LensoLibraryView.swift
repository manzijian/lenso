import SwiftUI

/// 图库视图 — 严格按参考图 4：
/// 侧栏（带计数徽章）+ 胶囊工具栏（全部时间 ▾）+ 网格（选中蓝框+勾角标）+ 底部合计与分享/删除
struct LensoLibraryView: View {
    let images: [LibraryImage]
    @State private var selectedIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var section: Section = .screenshots
    @State private var noteCount = 0
    var onOpenPreview: ((UUID) -> Void)? = nil
    @Environment(\.openWindow) private var openWindow

    enum Section { case screenshots, text }

    private let columns = [
        GridItem(.adaptive(minimum: 175, maximum: 260), spacing: 12)
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .background(sidebarGradient)

            VStack(spacing: 12) {
                if section == .screenshots {
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
                } else {
                    TextNotesView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(12)
            .background(mainGradient)
        }
        .frame(minWidth: 760, minHeight: 520)
        .clipShape(RoundedRectangle(
            cornerRadius: 20,
            style: .continuous
        ))
        // 参考图为浅色玻璃，固定浅色外观（否则深色模式下文字变白、对比度丢失）
        .environment(\.colorScheme, .light)
        .onAppear { noteCount = ScreenshotStore.shared.textNoteCount() }
        .onReceive(NotificationCenter.default.publisher(for: .textNotesChanged)) { _ in
            noteCount = ScreenshotStore.shared.textNoteCount()
        }
    }

    /// 蓝紫氛围背景（参考图 4）
    private var mainGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.92, blue: 1.00),
                    Color(red: 0.82, green: 0.86, blue: 0.99),
                    Color(red: 0.90, green: 0.87, blue: 1.00),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // 柔和光斑
            RadialGradient(colors: [Color.blue.opacity(0.18), .clear], center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: 400)
            RadialGradient(colors: [Color.purple.opacity(0.15), .clear], center: UnitPoint(x: 0.9, y: 0.85), startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
    }

    private var sidebarGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.985, green: 0.99, blue: 1.0),
                Color(red: 0.95, green: 0.96, blue: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(.black.opacity(0.06)).frame(width: 1)
        }
        .ignoresSafeArea()
    }

    // MARK: - 侧栏（带计数）

    private let navCounts: [String: Int] = [
        "最近": 24, "收藏": 18, "回收站": 12,
        "工作": 32, "生活": 28, "设计": 24, "其他": 44,
    ]

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            navigationItem("全部截图", icon: "folder.fill", count: images.count,
                           isPrimary: section == .screenshots)
                .onTapGesture { section = .screenshots }

            navigationItem("文字", icon: "text.alignleft",
                           count: noteCount,
                           isPrimary: section == .text)
                .onTapGesture {
                    section = .text
                    noteCount = ScreenshotStore.shared.textNoteCount()
                }

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
                .onTapGesture {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .padding(.horizontal, 12)
        .padding(.top, 44)   // 让开交通灯
        .padding(.bottom, 12)
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
                .foregroundStyle(isPrimary ? Color.blue : .primary.opacity(0.7))
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))
                .foregroundStyle(isPrimary ? Color.blue : .primary.opacity(0.8))
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(isPrimary ? Color.blue : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if isPrimary {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.55))
                    .shadow(color: Color.blue.opacity(0.15), radius: 6, y: 2)
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

    // MARK: - 工具栏（胶囊分段，白玻璃）

    private var toolbar: some View {
        HStack(spacing: 10) {
            // 网格/列表分段
            HStack(spacing: 2) {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(width: 30, height: 26)
                    .background(Capsule().fill(.white.opacity(0.95)))
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                Image(systemName: "list.bullet")
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(width: 30, height: 26)
            }

            // 全部时间 ▾
            HStack(spacing: 4) {
                Text("全部时间").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.9)))
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            .contentShape(Rectangle())

            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.65))
                .onTapGesture { SearchPanelController.shared.show() }
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.65))
        }
        .padding(6)
        .background(Capsule().fill(.white.opacity(0.55)))
        .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
    }

    // MARK: - 图片单元（选中蓝框 + 勾角标）

    private func imageCell(_ item: LibraryImage) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                Image(nsImage: item.thumbnail)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isSelected {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.blue, lineWidth: 2.5)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.blue.opacity(0.08)))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Color.blue)
                            .padding(7)
                    }
                } else {
                    // 白色细描边（浅底上区分图片边界）
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2)
                    .onEnded { onOpenPreview?(item.id) }
                    .exclusively(before: TapGesture().onEnded {
                        if isSelected {
                            selectedIDs.remove(item.id)
                        } else {
                            selectedIDs.insert(item.id)
                        }
                    })
            )
    }

    // MARK: - 底部（合计 + 操作）

    private var footer: some View {
        HStack {
            if selectedIDs.isEmpty {
                Text("\(images.count) 张截图")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.7))
            } else {
                Text("已选择 \(selectedIDs.count) 张 · \(totalSelectedSize)")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.7))
            }

            Spacer()

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14))
                .foregroundStyle(selectedIDs.isEmpty ? Color.primary.opacity(0.25) : .primary.opacity(0.75))
            Image(systemName: "trash")
                .font(.system(size: 14))
                .foregroundStyle(selectedIDs.isEmpty ? Color.primary.opacity(0.25) : .red)
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.55))
        }
        .padding(.horizontal, 8)
    }

    private var totalSelectedSize: String {
        // MVP：按选中数估算（真实大小接入后替换）
        let mb = Double(selectedIDs.count) * 2.3
        return String(format: "%.1f MB", mb)
    }
}
