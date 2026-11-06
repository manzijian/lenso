import SwiftUI
import AppKit

/// 图库视图模型 — 从 ScreenshotStore 加载真实数据
@Observable
@MainActor
final class LibraryViewModel {
    var records: [ScreenshotRecord] = []
    var selectedIDs: Set<UUID> = []

    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init() {
        load()
        observer = NotificationCenter.default.addObserver(
            forName: .screenshotSaved, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() {
        records = (try? ScreenshotStore.shared.list()) ?? []
    }

    var selectedCount: Int { selectedIDs.count }

    func toggle(_ id: UUID) {
        selectedIDs.formSymmetricDifference([id])
    }

    func deleteSelected() {
        let store = ScreenshotStore.shared
        for record in records where selectedIDs.contains(record.id) {
            try? store.delete(record)
        }
        selectedIDs.removeAll()
        load()
    }

    func copySelected() {
        let store = ScreenshotStore.shared
        guard let record = records.first(where: { selectedIDs.contains($0.id) }),
              let image = store.loadImage(record) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
