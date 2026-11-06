import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

/// 独立图片预览窗口 — 图片最大化、顶部悬浮玻璃工具栏、不裁切
struct PreviewWindowView: View {
    let screenshotID: UUID?

    @State private var hoveringToolbar = false
    @State private var zoom: CGFloat = 1
    @State private var image: CGImage?
    @State private var record: ScreenshotRecord?
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack(alignment: .top) {
            LensoAmbientBackground().ignoresSafeArea()

            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit) // 不裁切
                        .scaleEffect(zoom)
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
                } else {
                    ContentUnavailableView("图片不存在", systemImage: "photo.badge.exclamationmark")
                }
            }
            .padding(LensoSpacing.xl)
            .padding(.top, LensoSpacing.toolbarHeight)

            // 顶部悬浮工具栏
            LensoMaterials.glassContainer {
                HStack(spacing: LensoSpacing.s) {
                    ToolButton(icon: "doc.on.doc", label: "复制") { copyImage() }
                    ToolButton(icon: "square.and.arrow.up", label: "导出") { exportImage() }
                    Divider().frame(height: 20)
                    ToolButton(icon: "plus.magnifyingglass", label: "放大") { zoom = min(zoom + 0.25, 3) }
                    ToolButton(icon: "minus.magnifyingglass", label: "缩小") { zoom = max(zoom - 0.25, 1) }
                    ToolButton(icon: "arrow.counterclockwise", label: "原大") { zoom = 1 }
                    Divider().frame(height: 20)
                    ToolButton(icon: "trash", label: "删除", destructive: true) {
                        deleteAndClose()
                    }
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
        .task(id: screenshotID) {
            loadRecord()
        }
    }

    private func loadRecord() {
        guard let screenshotID else { return }
        let store = ScreenshotStore.shared
        let records = (try? store.list()) ?? []
        guard let r = records.first(where: { $0.id == screenshotID }) else { return }
        record = r
        image = store.loadImage(r)
    }

    private func copyImage() {
        guard let image else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    private func exportImage() {
        guard let record, let image else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = record.filename
        panel.allowedContentTypes = [.png]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            if let dest {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
        }
    }

    private func deleteAndClose() {
        guard let record else { return }
        try? ScreenshotStore.shared.delete(record)
        dismissWindow(id: "preview")
    }
}

private struct ToolButton: View {
    let icon: String
    let label: String
    var destructive = false
    var action: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
            Text(label).font(LensoTypography.caption)
        }
        .foregroundStyle(
            destructive && hovering ? LensoColors.danger
            : hovering ? LensoColors.accent : .primary
        )
        .frame(width: 44, height: 36)
        .background(
            RoundedRectangle(cornerRadius: LensoRadius.control)
                .fill(.primary.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { action?() }
        .animation(LensoAnimations.hover, value: hovering)
    }
}
