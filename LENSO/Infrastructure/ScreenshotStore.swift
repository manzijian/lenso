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
        for sub in ["Original", "Thumbnails"] {
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
            captured_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_captured_at ON screenshots(captured_at DESC);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
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
            fileSize: fileSize, capturedAt: capturedAt
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
        let sql = "SELECT id, filename, width, height, file_size, captured_at FROM screenshots ORDER BY captured_at DESC;"
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
            if let id = UUID(uuidString: idString) {
                records.append(ScreenshotRecord(id: id, filename: filename, width: width, height: height, fileSize: fileSize, capturedAt: capturedAt))
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
