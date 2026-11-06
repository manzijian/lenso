import SwiftUI
import AppKit

/// 主图库窗口 — LensoLibraryView（新视觉）+ 真实数据
struct LibraryWindowView: View {
    @State private var images: [LibraryImage] = []
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LensoLibraryView(images: images)
            .background(LensoAmbientBackground())
            .onAppear(perform: load)
            .onReceive(NotificationCenter.default.publisher(for: .screenshotSaved)) { _ in
                load()
            }
    }

    private func load() {
        let store = ScreenshotStore.shared
        let records = (try? store.list()) ?? []
        images = records.map { record in
            let thumb = store.loadThumbnail(record) ?? store.loadImage(record)
            let nsImage = thumb.map { NSImage(cgImage: $0, size: NSSize(width: $0.width / 2, height: $0.height / 2)) }
                ?? NSImage(size: NSSize(width: 40, height: 30))
            return LibraryImage(id: record.id, thumbnail: nsImage, sourceName: "LENSO")
        }
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
