import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

/// 独立图片预览窗口 — Apple 设计风格 + 经典克莱因蓝（International Klein Blue）
/// 沉浸式无边框视口 + 悬浮胶囊工具栏（缩放/导出/直接钉在桌面上）
struct PreviewWindowView: View {
    let screenshotID: UUID?

    @State private var zoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize? = nil
    @State private var image: CGImage?
    @State private var record: ScreenshotRecord?
    @State private var copied = false
    @State private var hostWindow: NSWindow? = nil
    @State private var scrollMonitor: Any? = nil
    @State private var keyMonitor: Any? = nil
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            // 自适应窗口背景 + 克莱因蓝微光
            Color(nsColor: .windowBackgroundColor)
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
                            .offset(panOffset)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(RoundedRectangle(cornerRadius: LensoRadius.thumbnail, style: .continuous))
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        guard zoom > 1.0 else { return }
                                        let base = dragStartOffset ?? panOffset
                                        if dragStartOffset == nil { dragStartOffset = panOffset }
                                        panOffset = CGSize(
                                            width: base.width + value.translation.width,
                                            height: base.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        dragStartOffset = nil
                                    }
                            )
                    }
                } else {
                    ContentUnavailableView("图片不存在", systemImage: "photo.badge.exclamationmark")
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            // 顶部悬浮工具栏（自适应悬浮胶囊 + 克莱因蓝高亮）
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
                            .lineLimit(1)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                            .shadow(color: Color.primary.opacity(0.06), radius: 3, y: 1)
                    )
                }

                Spacer()

                // 操作按钮组
                HStack(spacing: 10) {
                    ToolbarIcon(
                        icon: "minus.magnifyingglass",
                        label: "缩小",
                        disabled: zoom <= 0.5
                    ) {
                        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                            zoom = max(zoom - 0.25, 0.5)
                            if zoom <= 1.0 { panOffset = .zero }
                        }
                    }

                    Text("\(Int(round(zoom * 100)))%")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.82))
                        .monospacedDigit()
                        .lensoNumericTransition()
                        .lensoAnimation(LensoAnimations.snappy, value: Int(round(zoom * 100)), reduceMotion: reduceMotion)
                        .frame(minWidth: 38)

                    ToolbarIcon(
                        icon: "plus.magnifyingglass",
                        label: "放大",
                        disabled: zoom >= 4.0
                    ) {
                        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                            zoom = min(zoom + 0.25, 4.0)
                        }
                    }

                    ToolbarIcon(
                        icon: "arrow.counterclockwise",
                        label: "复位 100%",
                        disabled: abs(zoom - 1.0) < 0.001 && panOffset == .zero
                    ) {
                        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                            zoom = 1.0
                            panOffset = .zero
                        }
                    }

                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: 14)

                    // 直接钉在屏幕上
                    ToolbarIcon(icon: "pin.fill", label: "钉在屏幕上 (回到刚截图的状态)") {
                        if let image {
                            CaptureCoordinator.shared.pin(image: image)
                            dismissWindow()
                        }
                    }

                    ToolbarIcon(
                        icon: copied ? "checkmark" : "doc.on.doc",
                        label: copied ? "已复制到剪贴板" : "复制到剪贴板",
                        tint: copied ? .green : nil
                    ) {
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
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        .shadow(color: Color.primary.opacity(0.06), radius: 4, y: 1)
                )
            }
            .padding(.top, 10)
            .padding(.horizontal, 14)
        }
        .background(PreviewWindowAccessor { window in
            if hostWindow !== window {
                hostWindow = window
            }
        })
        .lensoColorScheme()
        .task(id: screenshotID) { loadRecord() }
        .onExitCommand { dismissWindow() }
        .onAppear {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
                let targetWindow = hostWindow ?? NSApp.keyWindow
                guard let targetWindow, event.window === targetWindow else { return event }
                let delta = event.scrollingDeltaY
                if abs(delta) > 0.05 {
                    zoom = min(max(zoom + (delta > 0 ? 0.08 : -0.08), 0.25), 5.0)
                    if zoom <= 1.0 { panOffset = .zero }
                }
                return event
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                let targetWindow = hostWindow ?? NSApp.keyWindow
                guard let targetWindow, event.window === targetWindow else { return event }
                if event.keyCode == 53 { // Esc
                    dismissWindow()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
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
        ClipboardMonitor.shared.markSelfWrite()
        SaveToastController.shared.show(title: "已复制到剪贴板", subtitle: record.filename, thumbnail: image)
        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
            copied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                    copied = false
                }
            }
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
}

private struct ToolbarIcon: View {
    let icon: String
    var label: String? = nil
    var disabled: Bool = false
    var tint: Color? = nil
    var action: (() -> Void)?
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    tint ?? (hovering && !disabled ? LensoColors.kleinBlueBright : Color.primary.opacity(0.85))
                )
                .opacity(disabled ? 0.35 : 1.0)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .lensoSymbolReplace()
        }
        .buttonStyle(LensoPressButtonStyle(scale: 0.90))
        .disabled(disabled)
        .onHover { hovering = $0 }
        .lensoAnimation(LensoAnimations.hover, value: hovering, reduceMotion: reduceMotion)
        .help(label ?? "")
    }
}

private struct PreviewWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}
