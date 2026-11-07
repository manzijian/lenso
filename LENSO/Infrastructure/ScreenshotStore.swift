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
        guard let filename = item.filename else { return nil }
        return Self.loadImage(at: baseDir.appendingPathComponent("Clipboard").appendingPathComponent(filename))
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
