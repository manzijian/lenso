import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SQLite3

struct ScreenshotRecord: Identifiable, Hashable {
    let id: UUID
    let filename: String
    let width: Int
    let height: Int
    let fileSize: Int
    let capturedAt: Date
    let isFavorite: Bool
    let favoritedAt: Date?
}

/// 文字收纳条目
struct TextNote: Identifiable {
    let id: UUID
    var content: String
    let sourceApp: String?
    let createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var favoritedAt: Date?
}

/// 剪贴板历史条目（图片或文字），记录来源应用
struct ClipboardItem: Identifiable {
    enum Kind: String { case image, text }
    let id: UUID
    let kind: Kind
    let filename: String?
    let text: String?
    let sourceApp: String?
    let createdAt: Date
}

/// MVP 持久层：原图/缩略图文件存储 + SQLite 索引（规范第九章简化版）
/// 目录结构：~/Library/Application Support/LENSO/{Original,Thumbnails,lenso.sqlite}
final class ScreenshotStore: @unchecked Sendable {
    static let shared = ScreenshotStore()

    private let db: OpaquePointer?
    private let baseDir: URL
    private let queue = DispatchQueue(label: "com.lenso.store", qos: .userInitiated)

    init(baseDirectory: URL? = nil) {
        baseDir = baseDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LENSO", isDirectory: true)
        for sub in ["Original", "Thumbnails", "Clipboard"] {
            try? FileManager.default.createDirectory(at: baseDir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        db = Self.openDB(at: baseDir.appendingPathComponent("lenso.sqlite"))
        Self.migrate(db: db)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database setup

    private static func openDB(at url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            return nil
        }
        return db
    }

    private static func migrate(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS screenshots (
            id TEXT PRIMARY KEY NOT NULL,
            filename TEXT NOT NULL,
            width INTEGER NOT NULL,
            height INTEGER NOT NULL,
            file_size INTEGER NOT NULL,
            captured_at REAL NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            favorited_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_captured_at ON screenshots(captured_at DESC);
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL,
            filename TEXT,
            text TEXT,
            source_app TEXT,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_clip_created ON clipboard_items(created_at DESC);
        CREATE TABLE IF NOT EXISTS text_notes (
            id TEXT PRIMARY KEY NOT NULL,
            content TEXT NOT NULL,
            source_app TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            favorited_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_note_created ON text_notes(created_at DESC);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
        // 旧表升级：补充 source_app 列（已存在则忽略错误）
        sqlite3_exec(db, "ALTER TABLE clipboard_items ADD COLUMN source_app TEXT;", nil, nil, nil)
        // 旧表升级：收藏列
        sqlite3_exec(db, "ALTER TABLE screenshots ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE screenshots ADD COLUMN favorited_at REAL;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE text_notes ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE text_notes ADD COLUMN favorited_at REAL;", nil, nil, nil)
    }

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func bind(_ stmt: OpaquePointer?, _ index: Int32, _ text: String) {
        sqlite3_bind_text(stmt, index, (text as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }

    // MARK: - Save

    @discardableResult
    func save(image: CGImage, capturedAt: Date = Date()) throws -> ScreenshotRecord {
        let id = UUID()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        let filename = "LENSO_\(formatter.string(from: capturedAt))_\(id.uuidString.prefix(6)).png"
        let imageURL = baseDir.appendingPathComponent("Original").appendingPathComponent(filename)

        // 原子写 PNG：临时文件 → rename
        let tempURL = baseDir.appendingPathComponent("Original").appendingPathComponent(".tmp-\(id.uuidString)")
        guard let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw StoreError.imageEncodeFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw StoreError.imageEncodeFailed
        }
        _ = try FileManager.default.replaceItemAt(imageURL, withItemAt: tempURL)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: imageURL.path)[.size] as? Int) ?? 0

        // 缩略图（宽 480，保持比例）
        let thumbSize = thumbnailSize(for: image)
        guard let thumb = image.resized(to: thumbSize) else { throw StoreError.thumbnailFailed }
        let thumbURL = baseDir.appendingPathComponent("Thumbnails").appendingPathComponent(filename)
        guard let thumbDest = CGImageDestinationCreateWithURL(thumbURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw StoreError.thumbnailFailed
        }
        CGImageDestinationAddImage(thumbDest, thumb, nil)
        guard CGImageDestinationFinalize(thumbDest) else {
            throw StoreError.thumbnailFailed
        }

        // INSERT
        let sql = "INSERT INTO screenshots (id, filename, width, height, file_size, captured_at) VALUES (?,?,?,?,?,?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
        defer { sqlite3_finalize(stmt) }
        Self.bind(stmt, 1, id.uuidString)
        Self.bind(stmt, 2, filename)
        sqlite3_bind_int(stmt, 3, Int32(image.width))
        sqlite3_bind_int(stmt, 4, Int32(image.height))
        sqlite3_bind_int64(stmt, 5, Int64(fileSize))
        sqlite3_bind_double(stmt, 6, capturedAt.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }

        return ScreenshotRecord(
            id: id, filename: filename,
            width: image.width, height: image.height,
            fileSize: fileSize, capturedAt: capturedAt,
            isFavorite: false, favoritedAt: nil
        )
    }

    private func thumbnailSize(for image: CGImage) -> CGSize {
        let targetWidth: CGFloat = 480
        let ratio = CGFloat(image.width) / CGFloat(image.height)
        return CGSize(width: targetWidth, height: targetWidth / ratio)
    }

    // MARK: - Query

    func list() throws -> [ScreenshotRecord] {
        try queue.sync { try listUnlocked() }
    }

    private func listUnlocked() throws -> [ScreenshotRecord] {
        let sql = "SELECT id, filename, width, height, file_size, captured_at, is_favorite, favorited_at FROM screenshots ORDER BY captured_at DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
        defer { sqlite3_finalize(stmt) }

        var records: [ScreenshotRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idString = String(cString: sqlite3_column_text(stmt, 0))
            let filename = String(cString: sqlite3_column_text(stmt, 1))
            let width = Int(sqlite3_column_int(stmt, 2))
            let height = Int(sqlite3_column_int(stmt, 3))
            let fileSize = Int(sqlite3_column_int64(stmt, 4))
            let capturedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            let isFavorite = sqlite3_column_int(stmt, 6) != 0
            let favoritedAt: Date? = sqlite3_column_type(stmt, 7) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
            if let id = UUID(uuidString: idString) {
                records.append(ScreenshotRecord(
                    id: id, filename: filename, width: width, height: height,
                    fileSize: fileSize, capturedAt: capturedAt,
                    isFavorite: isFavorite, favoritedAt: favoritedAt
                ))
            }
        }
        return records
    }

    // MARK: - Image loading

    func loadImage(_ record: ScreenshotRecord) -> CGImage? {
        Self.loadImage(at: baseDir.appendingPathComponent("Original").appendingPathComponent(record.filename))
    }

    func loadThumbnail(_ record: ScreenshotRecord) -> CGImage? {
        Self.loadImage(at: baseDir.appendingPathComponent("Thumbnails").appendingPathComponent(record.filename))
    }

    private static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Delete

    func delete(_ record: ScreenshotRecord) throws {
        try queue.sync {
            let sql = "DELETE FROM screenshots WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            Self.bind(stmt, 1, record.id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }

            for sub in ["Original", "Thumbnails"] {
                let url = baseDir.appendingPathComponent(sub).appendingPathComponent(record.filename)
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Favorites

    func setScreenshotFavorite(_ favorite: Bool, id: UUID) throws {
        try queue.sync {
            let sql = "UPDATE screenshots SET is_favorite = ?, favorited_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, favorite ? 1 : 0)
            if favorite {
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            Self.bind(stmt, 3, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }
        }
    }

    func setTextNoteFavorite(_ favorite: Bool, id: UUID) throws {
        try queue.sync {
            let sql = "UPDATE text_notes SET is_favorite = ?, favorited_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, favorite ? 1 : 0)
            if favorite {
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            Self.bind(stmt, 3, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }
        }
    }

    // MARK: - Text notes（文字收纳）

    @discardableResult
    func createTextNote(content: String, sourceApp: String? = nil) throws -> TextNote {
        let id = UUID()
        let now = Date()
        try queue.sync {
            let sql = "INSERT INTO text_notes (id, content, source_app, created_at, updated_at) VALUES (?,?,?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            Self.bind(stmt, 1, id.uuidString)
            Self.bind(stmt, 2, content)
            if let sourceApp { Self.bind(stmt, 3, sourceApp) } else { sqlite3_bind_null(stmt, 3) }
            sqlite3_bind_double(stmt, 4, now.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 5, now.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }
        }
        return TextNote(id: id, content: content, sourceApp: sourceApp,
                        createdAt: now, updatedAt: now,
                        isFavorite: false, favoritedAt: nil)
    }

    func listTextNotes() throws -> [TextNote] {
        try queue.sync {
            let sql = "SELECT id, content, source_app, created_at, updated_at, is_favorite, favorited_at FROM text_notes ORDER BY updated_at DESC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            var notes: [TextNote] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idText = sqlite3_column_text(stmt, 0),
                      let id = UUID(uuidString: String(cString: idText)),
                      let contentText = sqlite3_column_text(stmt, 1)
                else { continue }
                let sourceApp = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                let isFavorite = sqlite3_column_int(stmt, 5) != 0
                let favoritedAt: Date? = sqlite3_column_type(stmt, 6) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
                notes.append(TextNote(id: id, content: String(cString: contentText),
                                      sourceApp: sourceApp, createdAt: createdAt, updatedAt: updatedAt,
                                      isFavorite: isFavorite, favoritedAt: favoritedAt))
            }
            return notes
        }
    }

    func updateTextNote(id: UUID, content: String) throws {
        try queue.sync {
            let sql = "UPDATE text_notes SET content = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            Self.bind(stmt, 1, content)
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            Self.bind(stmt, 3, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }
        }
    }

    func deleteTextNote(id: UUID) throws {
        try queue.sync {
            let sql = "DELETE FROM text_notes WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            Self.bind(stmt, 1, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }
        }
    }

    func textNoteCount() -> Int {
        (try? queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM text_notes;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
        }) ?? 0
    }

    // MARK: - Clipboard history

    @discardableResult
    func saveClipboardImage(_ image: CGImage, sourceApp: String?) throws -> ClipboardItem {
        let id = UUID()
        let filename = "\(id.uuidString).png"
        let url = baseDir.appendingPathComponent("Clipboard").appendingPathComponent(filename)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw StoreError.imageEncodeFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw StoreError.imageEncodeFailed }

        let createdAt = Date()
        try insertClipboard(id: id, kind: .image, filename: filename, text: nil, sourceApp: sourceApp, createdAt: createdAt)
        return ClipboardItem(id: id, kind: .image, filename: filename, text: nil, sourceApp: sourceApp, createdAt: createdAt)
    }

    @discardableResult
    func saveClipboardText(_ text: String, sourceApp: String?) throws -> ClipboardItem {
        let id = UUID()
        let createdAt = Date()
        try insertClipboard(id: id, kind: .text, filename: nil, text: text, sourceApp: sourceApp, createdAt: createdAt)
        return ClipboardItem(id: id, kind: .text, filename: nil, text: text, sourceApp: sourceApp, createdAt: createdAt)
    }

    private func insertClipboard(id: UUID, kind: ClipboardItem.Kind, filename: String?, text: String?, sourceApp: String?, createdAt: Date) throws {
        try queue.sync {
            let sql = "INSERT INTO clipboard_items (id, kind, filename, text, source_app, created_at) VALUES (?,?,?,?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            Self.bind(stmt, 1, id.uuidString)
            Self.bind(stmt, 2, kind.rawValue)
            if let filename { Self.bind(stmt, 3, filename) } else { sqlite3_bind_null(stmt, 3) }
            if let text { Self.bind(stmt, 4, text) } else { sqlite3_bind_null(stmt, 4) }
            if let sourceApp { Self.bind(stmt, 5, sourceApp) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_double(stmt, 6, createdAt.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }

            // 保留最近 200 条，超出的删除并清理文件
            sqlite3_exec(db, """
                DELETE FROM clipboard_items WHERE id NOT IN (
                    SELECT id FROM clipboard_items ORDER BY created_at DESC LIMIT 200
                );
                """, nil, nil, nil)
        }
    }

    func listClipboard(limit: Int = 60) throws -> [ClipboardItem] {
        try queue.sync {
            let sql = "SELECT id, kind, filename, text, source_app, created_at FROM clipboard_items ORDER BY created_at DESC LIMIT ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))

            var items: [ClipboardItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idText = sqlite3_column_text(stmt, 0),
                      let id = UUID(uuidString: String(cString: idText)),
                      let kindText = sqlite3_column_text(stmt, 1),
                      let kind = ClipboardItem.Kind(rawValue: String(cString: kindText))
                else { continue }
                let filename = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let text = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                let sourceApp = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                items.append(ClipboardItem(id: id, kind: kind, filename: filename, text: text, sourceApp: sourceApp, createdAt: createdAt))
            }
            return items
        }
    }

    func loadClipboardImage(_ item: ClipboardItem) -> CGImage? {
        guard let url = clipboardImageURL(item) else { return nil }
        return Self.loadImage(at: url)
    }

    func clipboardImageURL(_ item: ClipboardItem) -> URL? {
        guard let filename = item.filename else { return nil }
        return baseDir.appendingPathComponent("Clipboard").appendingPathComponent(filename)
    }

    func screenshotOriginalURL(_ record: ScreenshotRecord) -> URL? {
        return baseDir.appendingPathComponent("Original").appendingPathComponent(record.filename)
    }

    func deleteClipboardItem(id: UUID) throws {
        try queue.sync {
            var filename: String?
            let querySql = "SELECT filename FROM clipboard_items WHERE id = ? LIMIT 1;"
            var queryStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySql, -1, &queryStmt, nil) == SQLITE_OK {
                Self.bind(queryStmt, 1, id.uuidString)
                if sqlite3_step(queryStmt) == SQLITE_ROW {
                    filename = sqlite3_column_text(queryStmt, 0).map { String(cString: $0) }
                }
                sqlite3_finalize(queryStmt)
            }
            if let filename {
                let fileUrl = baseDir.appendingPathComponent("Clipboard").appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: fileUrl)
            }

            let deleteSql = "DELETE FROM clipboard_items WHERE id = ?;"
            var deleteStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(deleteStmt) }
            Self.bind(deleteStmt, 1, id.uuidString)
            guard sqlite3_step(deleteStmt) == SQLITE_DONE else { throw StoreError.dbFailed }
        }
    }

    func clearClipboardHistory() throws {
        try queue.sync {
            sqlite3_exec(db, "DELETE FROM clipboard_items;", nil, nil, nil)
            let dir = baseDir.appendingPathComponent("Clipboard")
            if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files { try? FileManager.default.removeItem(at: file) }
            }
        }
    }

    // MARK: - Auto Cleanup (过期自动删除)

    struct CleanupResult {
        let deletedScreenshots: Int
        let deletedClipboardItems: Int
        let deletedTextNotes: Int
        var totalDeleted: Int { deletedScreenshots + deletedClipboardItems + deletedTextNotes }
    }

    @discardableResult
    func cleanupOlderThan(cutoff: Date, preserveFavorites: Bool = true) -> CleanupResult {
        var countScreenshots = 0
        var countClips = 0
        var countNotes = 0

        queue.sync {
            let cutoffSec = cutoff.timeIntervalSince1970

            // 1. 清理过期截图
            let favClause = preserveFavorites ? "AND is_favorite = 0" : ""
            let selScreenshots = "SELECT id, filename FROM screenshots WHERE captured_at < ? \(favClause);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selScreenshots, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, cutoffSec)
                var toDelete: [(String, String)] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
                       let fn = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }) {
                        toDelete.append((idStr, fn))
                    }
                }
                sqlite3_finalize(stmt)

                for (idStr, fn) in toDelete {
                    let delSql = "DELETE FROM screenshots WHERE id = ?;"
                    var delStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, delSql, -1, &delStmt, nil) == SQLITE_OK {
                        Self.bind(delStmt, 1, idStr)
                        if sqlite3_step(delStmt) == SQLITE_DONE {
                            countScreenshots += 1
                            for sub in ["Original", "Thumbnails"] {
                                let u = baseDir.appendingPathComponent(sub).appendingPathComponent(fn)
                                try? FileManager.default.removeItem(at: u)
                            }
                        }
                        sqlite3_finalize(delStmt)
                    }
                }
            }

            // 2. 清理过期剪贴板数据
            let selClips = "SELECT id, filename FROM clipboard_items WHERE created_at < ?;"
            var clipStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selClips, -1, &clipStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(clipStmt, 1, cutoffSec)
                var clipsToDelete: [(String, String?)] = []
                while sqlite3_step(clipStmt) == SQLITE_ROW {
                    if let idStr = sqlite3_column_text(clipStmt, 0).map({ String(cString: $0) }) {
                        let fn = sqlite3_column_text(clipStmt, 1).map({ String(cString: $0) })
                        clipsToDelete.append((idStr, fn))
                    }
                }
                sqlite3_finalize(clipStmt)

                for (idStr, fn) in clipsToDelete {
                    let delSql = "DELETE FROM clipboard_items WHERE id = ?;"
                    var delStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, delSql, -1, &delStmt, nil) == SQLITE_OK {
                        Self.bind(delStmt, 1, idStr)
                        if sqlite3_step(delStmt) == SQLITE_DONE {
                            countClips += 1
                            if let fn {
                                let u = baseDir.appendingPathComponent("Clipboard").appendingPathComponent(fn)
                                try? FileManager.default.removeItem(at: u)
                            }
                        }
                        sqlite3_finalize(delStmt)
                    }
                }
            }

            // 3. 清理过期便签
            let noteFavClause = preserveFavorites ? "AND is_favorite = 0" : ""
            let selNotes = "SELECT id FROM text_notes WHERE created_at < ? \(noteFavClause);"
            var noteStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selNotes, -1, &noteStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(noteStmt, 1, cutoffSec)
                var notesToDelete: [String] = []
                while sqlite3_step(noteStmt) == SQLITE_ROW {
                    if let idStr = sqlite3_column_text(noteStmt, 0).map({ String(cString: $0) }) {
                        notesToDelete.append(idStr)
                    }
                }
                sqlite3_finalize(noteStmt)

                for idStr in notesToDelete {
                    let delSql = "DELETE FROM text_notes WHERE id = ?;"
                    var delStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, delSql, -1, &delStmt, nil) == SQLITE_OK {
                        Self.bind(delStmt, 1, idStr)
                        if sqlite3_step(delStmt) == SQLITE_DONE {
                            countNotes += 1
                        }
                        sqlite3_finalize(delStmt)
                    }
                }
            }
        }

        let res = CleanupResult(
            deletedScreenshots: countScreenshots,
            deletedClipboardItems: countClips,
            deletedTextNotes: countNotes
        )

        if res.totalDeleted > 0 {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .libraryChanged, object: nil)
            }
        }
        return res
    }

    // MARK: - Analytics (统计看板数据)

    struct AnalyticsData {
        struct DailyStat: Identifiable {
            var id: String { dateString }
            let date: Date
            let dateString: String // "MM-dd"
            let fullDateString: String // "yyyy-MM-dd"
            let screenshotsCount: Int
            let textCount: Int
            var totalCount: Int { screenshotsCount + textCount }
        }

        struct HourlyStat: Identifiable {
            var id: Int { hour }
            let hour: Int // 0..23
            let screenshotsCount: Int
            let textCount: Int
            var totalCount: Int { screenshotsCount + textCount }
        }

        struct AppStat: Identifiable {
            var id: String { appName }
            let appName: String
            let count: Int
            let percentage: Double
        }

        let totalScreenshots: Int
        let totalTextClips: Int
        let totalNotes: Int
        let todayScreenshots: Int
        let todayTextClips: Int
        let totalDiskBytes: Int64
        let peakHour: Int
        let dailyStats: [DailyStat]
        let hourlyStats: [HourlyStat]
        let topApps: [AppStat]
    }

    func fetchAnalyticsData(scopeDays: Int = 14) -> AnalyticsData {
        let calendar = Calendar.current
        let now = Date()

        let allRecords = (try? list()) ?? []
        let allClips = (try? listClipboard(limit: 1000)) ?? []
        let allNotes = (try? listTextNotes()) ?? []

        var totalBytes: Int64 = 0
        for r in allRecords { totalBytes += Int64(r.fileSize) }

        var todayScreenshots = 0
        for r in allRecords where calendar.isDateInToday(r.capturedAt) {
            todayScreenshots += 1
        }

        var todayText = 0
        for c in allClips where c.kind == .text && calendar.isDateInToday(c.createdAt) {
            todayText += 1
        }

        // 1. 每日统计 (Daily)
        let dfShort = DateFormatter()
        dfShort.dateFormat = "MM-dd"
        let dfFull = DateFormatter()
        dfFull.dateFormat = "yyyy-MM-dd"

        var dailyMap: [String: (date: Date, shots: Int, texts: Int)] = [:]
        for i in 0..<scopeDays {
            if let d = calendar.date(byAdding: .day, value: -(scopeDays - 1 - i), to: now) {
                let key = dfFull.string(from: d)
                dailyMap[key] = (d, 0, 0)
            }
        }

        for r in allRecords {
            let key = dfFull.string(from: r.capturedAt)
            if var entry = dailyMap[key] {
                entry.shots += 1
                dailyMap[key] = entry
            }
        }
        for c in allClips where c.kind == .text {
            let key = dfFull.string(from: c.createdAt)
            if var entry = dailyMap[key] {
                entry.texts += 1
                dailyMap[key] = entry
            }
        }

        let sortedDailyKeys = dailyMap.keys.sorted()
        let dailyStats: [AnalyticsData.DailyStat] = sortedDailyKeys.compactMap { key in
            guard let entry = dailyMap[key] else { return nil }
            return AnalyticsData.DailyStat(
                date: entry.date,
                dateString: dfShort.string(from: entry.date),
                fullDateString: key,
                screenshotsCount: entry.shots,
                textCount: entry.texts
            )
        }

        // 2. 24小时分布统计 (Hourly 00:00 - 23:00)
        var hourlyShots = Array(repeating: 0, count: 24)
        var hourlyTexts = Array(repeating: 0, count: 24)

        for r in allRecords {
            let h = calendar.component(.hour, from: r.capturedAt)
            if h >= 0 && h < 24 { hourlyShots[h] += 1 }
        }
        for c in allClips where c.kind == .text {
            let h = calendar.component(.hour, from: c.createdAt)
            if h >= 0 && h < 24 { hourlyTexts[h] += 1 }
        }

        var peakH = 14
        var maxTotalInHour = -1
        var hourlyStats: [AnalyticsData.HourlyStat] = []
        for h in 0..<24 {
            let sCount = hourlyShots[h]
            let tCount = hourlyTexts[h]
            let sum = sCount + tCount
            if sum > maxTotalInHour {
                maxTotalInHour = sum
                peakH = h
            }
            hourlyStats.append(AnalyticsData.HourlyStat(
                hour: h,
                screenshotsCount: sCount,
                textCount: tCount
            ))
        }

        // 3. 来源应用排行 Top 5
        var appCounts: [String: Int] = [:]
        for c in allClips {
            let app = c.sourceApp?.trimmingCharacters(in: .whitespaces) ?? "未知应用"
            if !app.isEmpty { appCounts[app, default: 0] += 1 }
        }
        for n in allNotes {
            let app = n.sourceApp?.trimmingCharacters(in: .whitespaces) ?? "文字收纳"
            if !app.isEmpty { appCounts[app, default: 0] += 1 }
        }
        appCounts["截图", default: 0] += allRecords.count

        let totalAppActions = max(1, appCounts.values.reduce(0, +))
        let sortedApps = appCounts.sorted { $0.value > $1.value }.prefix(6)
        let topApps: [AnalyticsData.AppStat] = sortedApps.map { (k, v) in
            AnalyticsData.AppStat(
                appName: k,
                count: v,
                percentage: Double(v) / Double(totalAppActions)
            )
        }

        return AnalyticsData(
            totalScreenshots: allRecords.count,
            totalTextClips: allClips.filter { $0.kind == .text }.count,
            totalNotes: allNotes.count,
            todayScreenshots: todayScreenshots,
            todayTextClips: todayText,
            totalDiskBytes: totalBytes,
            peakHour: peakH,
            dailyStats: dailyStats,
            hourlyStats: hourlyStats,
            topApps: topApps
        )
    }

    enum StoreError: LocalizedError {
        case imageEncodeFailed
        case thumbnailFailed
        case dbFailed

        var errorDescription: String? {
            switch self {
            case .imageEncodeFailed: "图片编码失败"
            case .thumbnailFailed: "缩略图生成失败"
            case .dbFailed: "数据库操作失败"
            }
        }
    }
}

private extension CGImage {
    func resized(to size: CGSize) -> CGImage? {
        let colorSpace = self.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
