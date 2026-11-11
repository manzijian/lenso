import SwiftUI
import AppKit

/// 主图库窗口 — LensoLibraryView + 真实数据（透明浮窗由 WindowConfigurator 处理）
struct LibraryWindowView: View {
    @State private var images: [LibraryImage] = []
    @State private var records: [ScreenshotRecord] = []
    @State private var notes: [TextNote] = []
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LensoLibraryView(
            images: images,
            records: records,
            notes: notes,
            onOpenPreview: { id in
                openFloatingPreview(id)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .screenshotSaved)) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .textNotesChanged)) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryChanged)) { _ in load() }
    }

    /// 双击图片：以原生刚截图时的纯粹贴图形式浮现，告别被大窗口包裹的压抑感
    private func openFloatingPreview(_ id: UUID) {
        let store = ScreenshotStore.shared
        guard let record = records.first(where: { $0.id == id }),
              let cgImage = store.loadImage(record) else { return }
        CaptureCoordinator.shared.pin(image: cgImage, isPreview: true)
    }

    private func load() {
        let store = ScreenshotStore.shared
        records = (try? store.list()) ?? []
        notes = (try? store.listTextNotes()) ?? []
        images = records.map { record in
            let thumb = store.loadThumbnail(record) ?? store.loadImage(record)
            let nsImage = thumb.map {
                NSImage(cgImage: $0, size: NSSize(width: $0.width / 2, height: $0.height / 2))
            } ?? NSImage(size: NSSize(width: 40, height: 30))
            return LibraryImage(
                id: record.id,
                thumbnail: nsImage,
                sourceName: "lenso",
                isFavorite: record.isFavorite
            )
        }
    }
}

/// 环境背景 — Apple 设计风格，纯净质感 + 微妙克莱因蓝光晕
struct LensoAmbientBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
            RadialGradient(
                colors: [
                    LensoColors.kleinBlueBright.opacity(0.05),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 600
            )
        }
    }
}
