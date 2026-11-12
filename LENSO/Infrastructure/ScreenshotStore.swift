import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SQLite3
import os

let storeLog = Logger(subsystem: "com.lenso.app", category: "store")

struct ScreenshotRecord: Identifiable, Hashable, Sendable {
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
struct TextNote: Identifiable, Sendable {
    let id: UUID
    var content: String
    let sourceApp: String?
    let createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var favoritedAt: Date?
}

/// 剪贴板历史条目（图片或文字），记录来源应用
struct ClipboardItem: Identifiable, Sendable {
    enum Kind: String, Sendable { case image, text }
    let id: UUID
    let kind: Kind
    let filename: String?
    let text: String?
    let sourceApp: String?
    let createdAt: Date
}

/// MVP 持久层：原图/缩略图文件存储 + SQLite 索引
/// 目录结构：~/Library/Application Support/LENSO/{Original,Thumbnails,lenso.sqlite}
final class ScreenshotStore: @unchecked Sendable {
    static let shared: ScreenshotStore = {
        do {
            return try ScreenshotStore()
        } catch {
            fatalError("Failed to initialize ScreenshotStore.shared: \(error)")
        }
    }()

    let db: OpaquePointer?
    let baseDir: URL
    let queue = DispatchQueue(label: "com.lenso.store", qos: .userInitiated)

    init(baseDirectory: URL? = nil) throws {
        let dir = baseDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LENSO", isDirectory: true)
        baseDir = dir

        for sub in ["Original", "Thumbnails", "Clipboard"] {
            let subURL = dir.appendingPathComponent(sub)
            do {
                try FileManager.default.createDirectory(at: subURL, withIntermediateDirectories: true)
            } catch {
                storeLog.error("Failed to create store directory at \(subURL.path): \(error.localizedDescription)")
                throw StoreError.directoryCreationFailed(subURL, error.localizedDescription)
            }
        }

        let dbURL = dir.appendingPathComponent("lenso.sqlite")
        guard let openedDB = Self.openDB(at: dbURL) else {
            let msg = String(cString: sqlite3_errmsg(nil) ?? UnsafePointer("Unknown SQLite error"))
            storeLog.error("Failed to open SQLite database at \(dbURL.path): \(msg)")
            throw StoreError.dbOpenFailed(dbURL, msg)
        }
        db = openedDB
        Self.migrate(db: openedDB)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database setup

    static func openDB(at url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            return nil
        }
        // 启用 WAL 模式提高并发读写性能与抗断电崩溃能力
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        return db
    }

    static func migrate(db: OpaquePointer?) {
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
        CREATE INDEX IF NOT EXISTS idx_notes_updated ON text_notes(updated_at DESC);
        """
        sqlite3_exec(db, sql, nil, nil, nil)

        // 幂等补充列
        sqlite3_exec(db, "ALTER TABLE clipboard_items ADD COLUMN source_app TEXT;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE clipboard_items ADD COLUMN content_hash TEXT;", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_clip_hash ON clipboard_items(content_hash);", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE screenshots ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE screenshots ADD COLUMN favorited_at REAL;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE text_notes ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE text_notes ADD COLUMN favorited_at REAL;", nil, nil, nil)

        // 智能清理：对文本去重，只保留同一文本最近一次复制的时间记录，节省空间
        sqlite3_exec(db, """
        DELETE FROM clipboard_items
        WHERE kind = 'text' AND id NOT IN (
            SELECT c1.id FROM clipboard_items c1
            JOIN (
                SELECT text, MAX(created_at) as max_created
                FROM clipboard_items WHERE kind = 'text'
                GROUP BY text
            ) c2 ON c1.text = c2.text AND c1.created_at = c2.max_created
        );
        """, nil, nil, nil)
    }

    static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func bind(_ stmt: OpaquePointer?, _ index: Int32, _ text: String) {
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
            if FileManager.default.fileExists(atPath: tempURL.path) {
                do {
                    try FileManager.default.removeItem(at: tempURL)
                } catch {
                    storeLog.error("Failed to remove temp file at \(tempURL.path): \(error.localizedDescription)")
                }
            }
            throw StoreError.imageEncodeFailed
        }
        _ = try FileManager.default.replaceItemAt(imageURL, withItemAt: tempURL)

        let fileSize: Int
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: imageURL.path)
            fileSize = (attrs[.size] as? Int) ?? 0
        } catch {
            storeLog.error("Failed to read file size for \(imageURL.path): \(error.localizedDescription)")
            fileSize = 0
        }

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

        try queue.sync {
            let sql = "INSERT INTO screenshots (id, filename, width, height, file_size, captured_at) VALUES (?,?,?,?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            Self.bind(stmt, 1, id.uuidString)
            Self.bind(stmt, 2, filename)
            sqlite3_bind_int(stmt, 3, Int32(image.width))
            sqlite3_bind_int(stmt, 4, Int32(image.height))
            sqlite3_bind_int(stmt, 5, Int32(fileSize))
            sqlite3_bind_double(stmt, 6, capturedAt.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }
        }

        return ScreenshotRecord(
            id: id,
            filename: filename,
            width: image.width,
            height: image.height,
            fileSize: fileSize,
            capturedAt: capturedAt,
            isFavorite: false,
            favoritedAt: nil
        )
    }

    // MARK: - Query

    func list(limit: Int = 100) throws -> [ScreenshotRecord] {
        try queue.sync {
            let sql = "SELECT id, filename, width, height, file_size, captured_at, is_favorite, favorited_at FROM screenshots ORDER BY captured_at DESC LIMIT ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))

            var records: [ScreenshotRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idText = sqlite3_column_text(stmt, 0),
                      let id = UUID(uuidString: String(cString: idText)),
                      let fnText = sqlite3_column_text(stmt, 1)
                else { continue }
                let filename = String(cString: fnText)
                let width = Int(sqlite3_column_int(stmt, 2))
                let height = Int(sqlite3_column_int(stmt, 3))
                let size = Int(sqlite3_column_int(stmt, 4))
                let capturedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                let isFavorite = sqlite3_column_int(stmt, 6) != 0
                let favoritedAt: Date? = sqlite3_column_type(stmt, 7) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
                records.append(ScreenshotRecord(
                    id: id,
                    filename: filename,
                    width: width,
                    height: height,
                    fileSize: size,
                    capturedAt: capturedAt,
                    isFavorite: isFavorite,
                    favoritedAt: favoritedAt
                ))
            }
            return records
        }
    }

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
                if FileManager.default.fileExists(atPath: url.path) {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        storeLog.error("Failed to remove image file at \(url.path): \(error.localizedDescription)")
                    }
                }
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

    // MARK: - Loading

    func loadImage(_ record: ScreenshotRecord) -> CGImage? {
        let url = baseDir.appendingPathComponent("Original").appendingPathComponent(record.filename)
        return Self.loadImage(at: url)
    }

    func screenshotOriginalURL(_ record: ScreenshotRecord) -> URL? {
        return baseDir.appendingPathComponent("Original").appendingPathComponent(record.filename)
    }

    func loadThumbnail(_ record: ScreenshotRecord) -> CGImage? {
        let url = baseDir.appendingPathComponent("Thumbnails").appendingPathComponent(record.filename)
        return Self.loadImage(at: url)
    }

    func thumbnailURL(_ record: ScreenshotRecord) -> URL? {
        return baseDir.appendingPathComponent("Thumbnails").appendingPathComponent(record.filename)
    }

    static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func thumbnailSize(for image: CGImage) -> CGSize {
        let targetWidth: CGFloat = 480
        let scale = targetWidth / CGFloat(image.width)
        return CGSize(width: targetWidth, height: CGFloat(image.height) * scale)
    }

    enum StoreError: LocalizedError, Equatable {
        case directoryCreationFailed(URL, String)
        case dbOpenFailed(URL, String)
        case imageEncodeFailed
        case thumbnailFailed
        case dbFailed

        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed(let url, let reason):
                "目录创建失败 (\(url.path)): \(reason)"
            case .dbOpenFailed(let url, let reason):
                "数据库打开失败 (\(url.path)): \(reason)"
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
