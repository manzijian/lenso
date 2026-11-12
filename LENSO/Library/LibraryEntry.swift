import AppKit

/// 最近 / 收藏列表的统一条目：截图与文字按时间混排
struct LibraryEntry: Identifiable {
    enum Kind { case screenshot, note }

    let id: String
    let kind: Kind
    let date: Date
    let favoriteDate: Date?
    let thumbnail: NSImage?
    let screenshot: ScreenshotRecord?
    let note: TextNote?

    var isFavorite: Bool {
        screenshot?.isFavorite ?? note?.isFavorite ?? false
    }

    static func screenshot(_ record: ScreenshotRecord, thumbnail: NSImage?) -> LibraryEntry {
        LibraryEntry(
            id: "s:\(record.id.uuidString)",
            kind: .screenshot,
            date: record.capturedAt,
            favoriteDate: record.favoritedAt,
            thumbnail: thumbnail,
            screenshot: record,
            note: nil
        )
    }

    static func note(_ note: TextNote) -> LibraryEntry {
        LibraryEntry(
            id: "n:\(note.id.uuidString)",
            kind: .note,
            date: note.updatedAt,
            favoriteDate: note.favoritedAt,
            thumbnail: nil,
            screenshot: nil,
            note: note
        )
    }
}

extension Notification.Name {
    static let libraryChanged = Notification.Name("com.lenso.libraryChanged")
    static let textNotesChanged = Notification.Name("com.lenso.textNotesChanged")
}
