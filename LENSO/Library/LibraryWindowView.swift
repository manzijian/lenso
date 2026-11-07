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
                openWindow(id: "preview", value: id)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .screenshotSaved)) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .textNotesChanged)) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryChanged)) { _ in load() }
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
                sourceName: "LENSO",
                isFavorite: record.isFavorite
            )
        }
    }
}

/// 环境背景 — 蓝紫柔和光晕
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
