import Foundation
import SQLite3

extension ScreenshotStore {

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
        return TextNote(
            id: id,
            content: content,
            sourceApp: sourceApp,
            createdAt: now,
            updatedAt: now,
            isFavorite: false,
            favoritedAt: nil
        )
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
                notes.append(TextNote(
                    id: id,
                    content: String(cString: contentText),
                    sourceApp: sourceApp,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    isFavorite: isFavorite,
                    favoritedAt: favoritedAt
                ))
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

    /// 重新触碰便签，更新 updated_at 为当前时间，让再次复制或使用的内容立即跃升到时间倒序的最顶部
    func touchTextNote(id: UUID) throws {
        try queue.sync {
            let sql = "UPDATE text_notes SET updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            Self.bind(stmt, 2, id.uuidString)
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
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM text_notes;", -1, &stmt, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db) ?? UnsafePointer(""))
                storeLog.error("Failed to query textNoteCount: \(msg)")
                return 0
            }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
        }
    }
}
