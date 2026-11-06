import SwiftUI

/// 主图库窗口 — 窄侧栏 + 轻量工具栏 + 自适应网格 + 底部玻璃操作条
struct LibraryWindowView: View {
    @State private var viewModel = LibraryViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebar()
            VStack(spacing: 0) {
                LibraryToolbar(selectedCount: viewModel.selectedCount)
                ScreenshotGrid(viewModel: viewModel) { record in
                    openWindow(id: "preview", value: record.id)
                }
            }
        }
        .background(LensoAmbientBackground())
        .overlay(alignment: .bottom) {
            if viewModel.selectedCount > 0 {
                SelectionActionBar(
                    count: viewModel.selectedCount,
                    onCopy: { viewModel.copySelected() },
                    onDelete: { viewModel.deleteSelected() },
                    onClear: { viewModel.selectedIDs.removeAll() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(LensoAnimations.panel, value: viewModel.selectedCount)
        .onAppear { viewModel.load() }
    }
}

/// 环境背景 — 蓝紫柔和光晕（玻璃效果需要背景层次才显质感）
struct LensoAmbientBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            LinearGradient(
                colors: [
                    LensoColors.accent.opacity(0.10),
                    Color.clear,
                    Color(red: 0.62, green: 0.44, blue: 1.00).opacity(0.08),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

/// 左侧窄图标导航栏
struct LibrarySidebar: View {
    @State private var hoverID: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: LensoSpacing.xs) {
            SideIcon(systemName: "photo.on.rectangle.angled", label: "图库", id: "library", isActive: true, hoverID: $hoverID)
            SideIcon(systemName: "magnifyingglass", label: "搜索", id: "search", isActive: false, hoverID: $hoverID)
            SideIcon(systemName: "gearshape", label: "设置", id: "settings", isActive: false, hoverID: $hoverID) {
                openWindow(id: "settings")
            }
            Spacer()
        }
        .padding(.top, LensoSpacing.xl)
        .frame(width: LensoSpacing.sidebarWidth)
    }
}

private struct SideIcon: View {
    let systemName: String
    let label: String
    let id: String
    let isActive: Bool
    @Binding var hoverID: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemName)
                .font(.system(size: 17))
            Text(label).font(LensoTypography.caption)
        }
        .foregroundStyle(isActive ? LensoColors.accent : (hoverID == id ? .primary : .secondary))
        .frame(width: 52, height: 44)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: LensoRadius.control)
                    .fill(LensoColors.accent.opacity(0.14))
            } else if hoverID == id {
                RoundedRectangle(cornerRadius: LensoRadius.control)
                    .fill(.primary.opacity(0.05))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoverID = hovering ? id : nil
        }
        .onTapGesture { action?() }
        .animation(LensoAnimations.hover, value: hoverID)
    }
}

/// 顶部轻量工具栏
struct LibraryToolbar: View {
    let selectedCount: Int
    @State private var sortOrder = 0

    var body: some View {
        HStack(spacing: LensoSpacing.m) {
            Text("图库").font(LensoTypography.title)
            if selectedCount > 0 {
                Text("已选 \(selectedCount) 张").font(LensoTypography.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("排序", selection: $sortOrder) {
                Text("按时间").tag(0)
                Text("按应用").tag(1)
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
        .padding(.horizontal, LensoSpacing.xl)
        .frame(height: LensoSpacing.toolbarHeight)
    }
}

/// 图片网格 — 自适应列数，真实缩略图
struct ScreenshotGrid: View {
    let viewModel: LibraryViewModel
    let onOpen: (ScreenshotRecord) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: LensoSpacing.l)], spacing: LensoSpacing.l) {
                ForEach(viewModel.records) { record in
                    ThumbnailCell(
                        record: record,
                        isSelected: viewModel.selectedIDs.contains(record.id)
                    ) { id in
                        viewModel.toggle(id)
                    } onDoubleTap: {
                        onOpen(record)
                    }
                }
            }
            .padding(LensoSpacing.xl)
            .padding(.bottom, LensoSpacing.actionBarHeight + LensoSpacing.xl)
        }
        .overlay {
            if viewModel.records.isEmpty {
                ContentUnavailableView(
                    "还没有截图",
                    systemImage: "camera.viewfinder",
                    description: Text("点击菜单栏图标开始第一次截图")
                )
            }
        }
    }
}

/// 缩略图单元 — 图片是主体：无卡片边框，选中蓝描边 + 计数角标
struct ThumbnailCell: View {
    let record: ScreenshotRecord
    let isSelected: Bool
    let onToggle: (UUID) -> Void
    let onDoubleTap: () -> Void

    @State private var hovering = false
    @State private var thumbnail: CGImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: LensoRadius.thumbnail)
                        .fill(.quaternary.opacity(0.4))
                        .aspectRatio(16 / 10, contentMode: .fit)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Text("LENSO").font(LensoTypography.caption)
                    Spacer()
                    Text(record.capturedAt, style: .time).font(LensoTypography.caption)
                }
                .foregroundStyle(.white)
                .padding(LensoSpacing.s)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: LensoRadius.thumbnail))
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: LensoRadius.thumbnail))

            if isSelected {
                Image(systemName: "checkmark")
                    .font(LensoTypography.badge)
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(LensoColors.accent))
                    .padding(LensoSpacing.s)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LensoRadius.thumbnail)
                .strokeBorder(
                    isSelected ? LensoColors.accent : Color.clear,
                    lineWidth: 3
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: LensoRadius.thumbnail)
                .strokeBorder(.white.opacity(hovering && !isSelected ? 0.5 : 0), lineWidth: 2)
        }
        .opacity(isSelected ? 0.85 : 1)
        .scaleEffect(hovering ? 1.015 : 1)
        .clipShape(RoundedRectangle(cornerRadius: LensoRadius.thumbnail))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onToggle(record.id) }
        .animation(LensoAnimations.hover, value: hovering)
        .animation(LensoAnimations.hover, value: isSelected)
        .task(id: record.id) {
            thumbnail = ScreenshotStore.shared.loadThumbnail(record)
        }
    }
}

/// 底部玻璃操作条 — 选中数量与操作
struct SelectionActionBar: View {
    let count: Int
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onClear: () -> Void

    var body: some View {
        LensoMaterials.glassContainer {
            HStack(spacing: LensoSpacing.m) {
                Text("已选 \(count) 张")
                    .font(LensoTypography.callout)
                Divider().frame(height: 18)
                Button(action: onCopy) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
                Spacer()
                Button(action: onClear) {
                    Label("取消", systemImage: "xmark")
                }
            }
            .font(LensoTypography.body)
            .tint(LensoColors.accent)
            .padding(.horizontal, LensoSpacing.l)
            .padding(.vertical, LensoSpacing.s)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.bottom, LensoSpacing.xl)
    }
}
