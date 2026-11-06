import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

/// 独立图片预览窗口（参考图 4 右侧）：
/// 图片满幅、顶部右侧图标工具条（放大/缩小/裁剪/返回/标注/取色/分享）
struct PreviewWindowView: View {
    let screenshotID: UUID?

    @State private var zoom: CGFloat = 1
    @State private var image: CGImage?
    @State private var record: ScreenshotRecord?
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack(alignment: .top) {
            // 浅色玻璃底
            LinearGradient(
                colors: [Color(red: 0.94, green: 0.96, blue: 1.0), Color(red: 0.88, green: 0.90, blue: 0.99)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // 图片满幅（不裁切）
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoom)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                } else {
                    ContentUnavailableView("图片不存在", systemImage: "photo.badge.exclamationmark")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 44)
            .padding(.bottom, 12)

            // 顶部图标条（右侧，参考图 4 预览窗）
            HStack {
                Spacer()
                HStack(spacing: 18) {
                    ToolbarIcon(icon: "plus.magnifyingglass") { zoom = min(zoom + 0.25, 3) }
                    ToolbarIcon(icon: "minus.magnifyingglass") { zoom = max(zoom - 0.25, 1) }
                    ToolbarIcon(icon: "crop") {}
                    ToolbarIcon(icon: "chevron.left") {}
                    ToolbarIcon(icon: "pencil.tip") {}
                    ToolbarIcon(icon: "eyedropper") {}
                    ToolbarIcon(icon: "square.and.arrow.up") { exportImage() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .environment(\.colorScheme, .light)
        .task(id: screenshotID) { loadRecord() }
    }

    private func loadRecord() {
        guard let screenshotID else { return }
        let store = ScreenshotStore.shared
        let records = (try? store.list()) ?? []
        guard let r = records.first(where: { $0.id == screenshotID }) else { return }
        record = r
        image = store.loadImage(r)
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
}

private struct ToolbarIcon: View {
    let icon: String
    var action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(hovering ? Color(nsColor: .controlAccentColor) : .primary.opacity(0.75))
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { action?() }
    }
}
