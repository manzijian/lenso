import SwiftUI

/// 独立图片预览窗口 — 图片最大化、顶部悬浮玻璃工具栏、不裁切
struct PreviewWindowView: View {
    let screenshotID: UUID?

    @State private var hoveringToolbar = false
    @State private var zoom: CGFloat = 1

    var body: some View {
        ZStack(alignment: .top) {
            LensoAmbientBackground().ignoresSafeArea()

            // 图片主体 — fit 不裁切
            RoundedRectangle(cornerRadius: LensoRadius.window)
                .fill(
                    LinearGradient(
                        colors: [LensoColors.accent.opacity(0.55), Color(red: 0.62, green: 0.44, blue: 1.00).opacity(0.45)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .aspectRatio(16 / 10, contentMode: .fit)
                .padding(LensoSpacing.xl)
                .padding(.top, LensoSpacing.toolbarHeight)
                .scaleEffect(zoom)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 10)

            // 顶部悬浮工具栏
            LensoMaterials.glassContainer {
                HStack(spacing: LensoSpacing.s) {
                    ToolButton(icon: "pin", label: "置顶")
                    ToolButton(icon: "pencil.tip.crop.circle", label: "编辑")
                    ToolButton(icon: "doc.text.viewfinder", label: "OCR")
                    ToolButton(icon: "translate", label: "翻译")
                    Divider().frame(height: 20)
                    ToolButton(icon: "square.and.arrow.up", label: "导出")
                    ToolButton(icon: "square.and.arrow.down.on.square", label: "原图")
                    Divider().frame(height: 20)
                    ToolButton(icon: "plus.magnifyingglass", label: "放大") { zoom = min(zoom + 0.25, 3) }
                    ToolButton(icon: "minus.magnifyingglass", label: "缩小") { zoom = max(zoom - 0.25, 1) }
                }
                .padding(.horizontal, LensoSpacing.s)
                .padding(.vertical, LensoSpacing.xs)
                .glassEffect(.regular, in: Capsule())
            }
            .padding(.top, LensoSpacing.m)
            .opacity(hoveringToolbar ? 1 : 0.85)
            .onHover { hoveringToolbar = $0 }
            .animation(LensoAnimations.fade, value: hoveringToolbar)
        }
    }
}

private struct ToolButton: View {
    let icon: String
    let label: String
    var action: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
            Text(label).font(LensoTypography.caption)
        }
        .foregroundStyle(hovering ? LensoColors.accent : .primary)
        .frame(width: 44, height: 36)
        .background(
            RoundedRectangle(cornerRadius: LensoRadius.control)
                .fill(.primary.opacity(hovering ? 0.06 : 0))
        )
        .onHover { hovering = $0 }
        .onTapGesture { action?() }
        .animation(LensoAnimations.hover, value: hovering)
    }
}
