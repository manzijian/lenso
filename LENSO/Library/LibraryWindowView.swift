import SwiftUI
import AppKit

/// 主图库窗口 — LensoLibraryView + 真实数据（透明浮窗由 WindowConfigurator 处理）
struct LibraryWindowView: View {
    @State private var images: [LibraryImage] = []
    @State private var records: [ScreenshotRecord] = []
    @State private var notes: [TextNote] = []
    @State private var pendingLoad: Task<Void, Never>?
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
        .onReceive(NotificationCenter.default.publisher(for: .screenshotSaved)) { _ in scheduleLoad() }
        .onReceive(NotificationCenter.default.publisher(for: .textNotesChanged)) { _ in scheduleLoad() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryChanged)) { _ in scheduleLoad() }
    }

    /// 双击图片：以原生刚截图时的纯粹贴图形式浮现，告别被大窗口包裹的压抑感
    private func openFloatingPreview(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        Task {
            guard let cgImage = await ScreenshotStore.loadImageAsync(record) else { return }
            CaptureCoordinator.shared.pin(image: cgImage, isPreview: true)
        }
    }

    /// 多条通知合并成一次刷新，避免一次复制触发多轮全量加载
    private func scheduleLoad() {
        pendingLoad?.cancel()
        pendingLoad = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            load()
        }
    }

    private func load() {
        Task {
            let result = await Self.loadLibrary()
            records = result.records
            notes = result.notes
            images = result.images
        }
    }

    private struct LibraryLoadResult: @unchecked Sendable {
        let records: [ScreenshotRecord]
        let notes: [TextNote]
        let images: [LibraryImage]
    }

    /// 读库与缩略图解码都放在主线程之外，打开/刷新窗口不再卡顿。
    nonisolated private static func loadLibrary() async -> LibraryLoadResult {
        let store = ScreenshotStore.shared
        let records = (try? store.list()) ?? []
        let notes = (try? store.listTextNotes()) ?? []
        let images = records.map { record -> LibraryImage in
            // 图库用 320px 解码即可（足够 200pt 卡片与 88pt 列表行），避免整库常驻大图
            let thumb = store.loadThumbnail(record, maxPixelSize: 320)
                ?? store.screenshotOriginalURL(record).flatMap {
                    ScreenshotStore.loadThumbnail(at: $0, maxPixelSize: 320)
                }
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
        return LibraryLoadResult(records: records, notes: notes, images: images)
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
