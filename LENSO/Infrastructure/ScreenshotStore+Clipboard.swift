import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SQLite3
import CryptoKit

extension ScreenshotStore {

    // MARK: - Hashing & Deduplication

    /// 计算图片的确定性特征指纹（用于去重与磁盘空间优化）
    static func computeImageHash(_ image: CGImage) -> String {
        if let provider = image.dataProvider, let cfData = provider.data {
            let digest = SHA256.hash(data: cfData as Data)
            return "\(image.width)x\(image.height):" + digest.map { String(format: "%02x", $0) }.joined()
        }
        let mutableData = NSMutableData()
        if let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            if CGImageDestinationFinalize(dest) {
                let digest = SHA256.hash(data: mutableData as Data)
                return "\(image.width)x\(image.height):" + digest.map { String(format: "%02x", $0) }.joined()
            }
        }
        return "\(image.width)x\(image.height)"
    }

    /// 计算纯文本的 SHA256 哈希
    static func computeTextHash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Clipboard history

    @discardableResult
    func saveClipboardImage(_ image: CGImage, sourceApp: String?) throws -> ClipboardItem {
        let now = Date()
        let hash = Self.computeImageHash(image)

        // 1. 查找是否已存在相同指纹的图片记录
        var matched: (id: UUID, filename: String)?
        try queue.sync {
            let sql = "SELECT id, filename FROM clipboard_items WHERE kind = 'image' AND content_hash = ? LIMIT 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                Self.bind(stmt, 1, hash)
                if sqlite3_step(stmt) == SQLITE_ROW,
                   let idStr = sqlite3_column_text(stmt, 0),
                   let id = UUID(uuidString: String(cString: idStr)),
                   let fnStr = sqlite3_column_text(stmt, 1) {
                    matched = (id, String(cString: fnStr))
                }
            }
        }

        if let matched {
            let fileUrl = baseDir.appendingPathComponent("Clipboard").appendingPathComponent(matched.filename)
            if FileManager.default.fileExists(atPath: fileUrl.path) {
                // 文件依然完好：无需重复编码写入磁盘（节省宝贵空间），直接更新时间为最新秒数，排在最前面！
                try queue.sync {
                    let sql = "UPDATE clipboard_items SET created_at = ?, source_app = ? WHERE id = ?;"
                    var stmt: OpaquePointer?
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
                    defer { sqlite3_finalize(stmt) }
                    sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
                    if let sourceApp { Self.bind(stmt, 2, sourceApp) } else { sqlite3_bind_null(stmt, 2) }
                    Self.bind(stmt, 3, matched.id.uuidString)
                    guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }
                }
                return ClipboardItem(id: matched.id, kind: .image, filename: matched.filename, text: nil, sourceApp: sourceApp, createdAt: now)
            }
        }

        // 2. 不存在或文件丢失：编码写入新 PNG
        let id = UUID()
        let filename = "\(id.uuidString).png"
        let url = baseDir.appendingPathComponent("Clipboard").appendingPathComponent(filename)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw StoreError.imageEncodeFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw StoreError.imageEncodeFailed }

        try insertClipboard(id: id, kind: .image, filename: filename, text: nil, sourceApp: sourceApp, createdAt: now, contentHash: hash)
        return ClipboardItem(id: id, kind: .image, filename: filename, text: nil, sourceApp: sourceApp, createdAt: now)
    }

    @discardableResult
    func saveClipboardText(_ text: String, sourceApp: String?) throws -> ClipboardItem {
        let now = Date()
        let hash = Self.computeTextHash(text)

        // 1. 查找是否已存在相同文本的记录
        var matchedID: UUID?
        try queue.sync {
            let sql = "SELECT id FROM clipboard_items WHERE kind = 'text' AND (content_hash = ? OR text = ?) LIMIT 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                Self.bind(stmt, 1, hash)
                Self.bind(stmt, 2, text)
                if sqlite3_step(stmt) == SQLITE_ROW,
                   let idStr = sqlite3_column_text(stmt, 0),
                   let id = UUID(uuidString: String(cString: idStr)) {
                    matchedID = id
                }
            }
        }

        if let matchedID {
            // 已存在：直接更新时间戳为当前最新时间，并更新 content_hash，不再插入重复记录！
            try queue.sync {
                let sql = "UPDATE clipboard_items SET created_at = ?, source_app = ?, content_hash = ? WHERE id = ?;"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
                if let sourceApp { Self.bind(stmt, 2, sourceApp) } else { sqlite3_bind_null(stmt, 2) }
                Self.bind(stmt, 3, hash)
                Self.bind(stmt, 4, matchedID.uuidString)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }
            }
            return ClipboardItem(id: matchedID, kind: .text, filename: nil, text: text, sourceApp: sourceApp, createdAt: now)
        }

        // 2. 不存在：插入新记录
        let id = UUID()
        try insertClipboard(id: id, kind: .text, filename: nil, text: text, sourceApp: sourceApp, createdAt: now, contentHash: hash)
        return ClipboardItem(id: id, kind: .text, filename: nil, text: text, sourceApp: sourceApp, createdAt: now)
    }

    private func insertClipboard(id: UUID, kind: ClipboardItem.Kind, filename: String?, text: String?, sourceApp: String?, createdAt: Date, contentHash: String? = nil) throws {
        try queue.sync {
            let sql = "INSERT INTO clipboard_items (id, kind, filename, text, source_app, created_at, content_hash) VALUES (?,?,?,?,?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            Self.bind(stmt, 1, id.uuidString)
            Self.bind(stmt, 2, kind.rawValue)
            if let filename { Self.bind(stmt, 3, filename) } else { sqlite3_bind_null(stmt, 3) }
            if let text { Self.bind(stmt, 4, text) } else { sqlite3_bind_null(stmt, 4) }
            if let sourceApp { Self.bind(stmt, 5, sourceApp) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_double(stmt, 6, createdAt.timeIntervalSince1970)
            if let contentHash { Self.bind(stmt, 7, contentHash) } else { sqlite3_bind_null(stmt, 7) }
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
                if FileManager.default.fileExists(atPath: fileUrl.path) {
                    do {
                        try FileManager.default.removeItem(at: fileUrl)
                    } catch {
                        storeLog.error("Failed to remove clipboard file at \(fileUrl.path): \(error.localizedDescription)")
                    }
                }
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
            do {
                let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                for file in files {
                    do {
                        try FileManager.default.removeItem(at: file)
                    } catch {
                        storeLog.error("Failed to remove clipboard history file at \(file.path): \(error.localizedDescription)")
                    }
                }
            } catch {
                storeLog.error("Failed to list files in clipboard directory \(dir.path): \(error.localizedDescription)")
            }
        }
    }
}
