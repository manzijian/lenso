import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

/// 独立图片预览窗口 — Apple 设计风格 + 经典克莱因蓝（International Klein Blue）
/// 沉浸式无边框视口 + 悬浮胶囊工具栏（缩放/导出/直接钉在桌面上）
struct PreviewWindowView: View {
    let screenshotID: UUID?

    @State private var zoom: CGFloat = 1
    @State private var image: CGImage?
    @State private var record: ScreenshotRecord?
    @State private var scrollMonitor: Any? = nil
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack(alignment: .top) {
            // Apple 原生极简白质感背景
            Color(red: 0.985, green: 0.988, blue: 0.995)
                .overlay {
                    RadialGradient(
                        colors: [LensoColors.kleinBlueBright.opacity(0.04), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 500
                    )
                }
                .ignoresSafeArea()

            // 图片主视口：沉浸贴合，绝不产生笨重的被大白边包裹感
            Group {
                if let image {
                    GeometryReader { geo in
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(zoom)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                } else {
                    ContentUnavailableView("图片不存在", systemImage: "photo.badge.exclamationmark")
                }
            }
            .padding(.top, 38)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            // 顶部悬浮工具栏（纯白 Apple 悬浮胶囊 + 克莱因蓝高亮）
            HStack {
                // 尺寸与文件名徽标
                if let record {
                    HStack(spacing: 6) {
                        Text(record.filename)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text("·")
                        Text("\(record.width) × \(record.height)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.92))
                            .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                    )
                }

                Spacer()

                // 操作按钮组
                HStack(spacing: 12) {
                    ToolbarIcon(icon: "plus.magnifyingglass", label: "放大") {
                        zoom = min(zoom + 0.25, 4.0)
                    }
                    ToolbarIcon(icon: "minus.magnifyingglass", label: "缩小") {
                        zoom = max(zoom - 0.25, 0.5)
                    }
                    ToolbarIcon(icon: "arrow.counterclockwise", label: "复位 100%") {
                        zoom = 1.0
                    }

                    Divider().frame(height: 14).opacity(0.5)

                    // 直接钉在屏幕上
                    ToolbarIcon(icon: "pin.fill", label: "钉在屏幕上 (回到刚截图的状态)") {
                        if let image {
                            CaptureCoordinator.shared.pin(image: image)
                            dismissWindow()
                        }
                    }

                    ToolbarIcon(icon: "doc.on.doc", label: "复制到剪贴板") {
                        copyImage()
                    }

                    ToolbarIcon(icon: "square.and.arrow.up", label: "导出图片") {
                        exportImage()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
                )
            }
            .padding(.top, 10)
            .padding(.horizontal, 14)
        }
        .lensoColorScheme()
        .task(id: screenshotID) { loadRecord() }
        .onAppear {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
                let delta = event.scrollingDeltaY
                if abs(delta) > 0.05 {
                    zoom = min(max(zoom + (delta > 0 ? 0.08 : -0.08), 0.25), 5.0)
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
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
        guard let image, let record else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        SaveToastController.shared.show(title: "已复制到剪贴板", subtitle: record.filename, thumbnail: image)
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
    var label: String? = nil
    var action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? LensoColors.kleinBlueBright : Color(red: 0.18, green: 0.18, blue: 0.22))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label ?? "")
    }
}
