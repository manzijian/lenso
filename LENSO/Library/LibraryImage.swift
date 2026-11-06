import AppKit

/// 图库条目模型 — 桥接 ScreenshotRecord 到 UI
struct LibraryImage: Identifiable {
    let id: UUID
    let thumbnail: NSImage
    let sourceName: String
}
