import SwiftUI

/// 主图库窗口 — 窄侧栏 + 轻量工具栏 + 自适应网格 + 底部玻璃操作条
struct LibraryWindowView: View {
    @State private var viewModel = LibraryViewModel()

    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebar()
            VStack(spacing: 0) {
                LibraryToolbar(selectedCount: viewModel.selectedCount)
                ScreenshotGrid(viewModel: viewModel)
            }
        }
        .background(LensoAmbientBackground())
        .overlay(alignment: .bottom) {
            if viewModel.selectedCount > 0 {
                SelectionActionBar(count: viewModel.selectedCount) {
                    viewModel.selectedIDs.removeAll()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(LensoAnimations.panel, value: viewModel.selectedCount)
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

    var body: some View {
        VStack(spacing: LensoSpacing.xs) {
            SideIcon(systemName: "photo.on.rectangle.angled", label: "图库", id: "library", isActive: true, hoverID: $hoverID)
            SideIcon(systemName: "magnifyingglass", label: "搜索", id: "search", isActive: false, hoverID: $hoverID)
            SideIcon(systemName: "gearshape", label: "设置", id: "settings", isActive: false, hoverID: $hoverID)
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
        .onHover { hovering in
            hoverID = hovering ? id : nil
        }
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
            Spacer()
            Picker("排序", selection: $sortOrder) {
                Text("按时间").tag(0)
                Text("按应用").tag(1)
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, LensoSpacing.xl)
        .frame(height: LensoSpacing.toolbarHeight)
    }
}

/// 图片网格 — 自适应列数，保持原始比例，统一圆角
struct ScreenshotGrid: View {
    let viewModel: LibraryViewModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: LensoSpacing.l)], spacing: LensoSpacing.l) {
                ForEach(viewModel.screenshots) { item in
                    ThumbnailCell(
                        item: item,
                        isSelected: viewModel.selectedIDs.contains(item.id)
                    ) { id in
                        viewModel.selectedIDs.formSymmetricDifference([id])
                    }
                }
            }
            .padding(LensoSpacing.xl)
            .padding(.bottom, LensoSpacing.actionBarHeight + LensoSpacing.xl)
        }
    }
}

/// 缩略图单元 — 图片是主体：无卡片边框，选中蓝描边 + 计数角标
struct ThumbnailCell: View {
    let item: ScreenshotItem
    let isSelected: Bool
    let onToggle: (UUID) -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: LensoRadius.thumbnail)
                .fill(item.gradient)
                .aspectRatio(16 / 10, contentMode: .fit)

            // 元信息条
            VStack {
                Spacer()
                HStack {
                    Text(item.appName).font(LensoTypography.caption)
                    Spacer()
                    Text(item.capturedAt, style: .time).font(LensoTypography.caption)
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
                Text("\(selectionIndex)")
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
        .onHover { hovering = $0 }
        .onTapGesture { onToggle(item.id) }
        .animation(LensoAnimations.hover, value: hovering)
        .animation(LensoAnimations.hover, value: isSelected)
    }

    private var selectionIndex: Int {
        1 // 批量选中序号；真实实现由 viewModel 传入
    }
}

/// 底部玻璃操作条 — 选中数量与操作
struct SelectionActionBar: View {
    let count: Int
    let onClear: () -> Void

    var body: some View {
        LensoMaterials.glassContainer {
            HStack(spacing: LensoSpacing.m) {
                Text("已选 \(count) 张")
                    .font(LensoTypography.callout)
                Divider().frame(height: 18)
                Button {
                } label: {
                    Label("置顶", systemImage: "pin")
                }
                Button {
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                } label: {
                    Label("删除", systemImage: "trash")
                }
                Spacer()
                Button {
                    onClear()
                } label: {
                    Label("取消", systemImage: "xmark")
                }
            }
            .font(LensoTypography.body)
            .buttonStyle(.glassProminent)
            .tint(LensoColors.accent)
            .padding(.horizontal, LensoSpacing.l)
            .padding(.vertical, LensoSpacing.s)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.bottom, LensoSpacing.xl)
    }
}
