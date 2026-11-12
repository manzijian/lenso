import Foundation
import SQLite3

extension ScreenshotStore {

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
                                if FileManager.default.fileExists(atPath: u.path) {
                                    do {
                                        try FileManager.default.removeItem(at: u)
                                    } catch {
                                        storeLog.error("Failed to remove cleanup screenshot file at \(u.path): \(error.localizedDescription)")
                                    }
                                }
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
                                if FileManager.default.fileExists(atPath: u.path) {
                                    do {
                                        try FileManager.default.removeItem(at: u)
                                    } catch {
                                        storeLog.error("Failed to remove cleanup clipboard file at \(u.path): \(error.localizedDescription)")
                                    }
                                }
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

        let allRecords: [ScreenshotRecord]
        do {
            allRecords = try list()
        } catch {
            storeLog.error("fetchAnalyticsData failed to list screenshots: \(error.localizedDescription)")
            allRecords = []
        }

        let allClips: [ClipboardItem]
        do {
            allClips = try listClipboard(limit: 1000)
        } catch {
            storeLog.error("fetchAnalyticsData failed to list clipboard: \(error.localizedDescription)")
            allClips = []
        }

        let allNotes: [TextNote]
        do {
            allNotes = try listTextNotes()
        } catch {
            storeLog.error("fetchAnalyticsData failed to list text notes: \(error.localizedDescription)")
            allNotes = []
        }

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

        var dailyMap: [String: (date: Date, full: String, sc: Int, tc: Int)] = [:]
        for i in (0..<scopeDays).reversed() {
            if let d = calendar.date(byAdding: .day, value: -i, to: now) {
                let shortKey = dfShort.string(from: d)
                let fullKey = dfFull.string(from: d)
                dailyMap[shortKey] = (d, fullKey, 0, 0)
            }
        }

        for r in allRecords {
            let shortKey = dfShort.string(from: r.capturedAt)
            if var val = dailyMap[shortKey] {
                val.sc += 1
                dailyMap[shortKey] = val
            }
        }
        for c in allClips where c.kind == .text {
            let shortKey = dfShort.string(from: c.createdAt)
            if var val = dailyMap[shortKey] {
                val.tc += 1
                dailyMap[shortKey] = val
            }
        }

        let dailyStats = dailyMap.values
            .sorted(by: { $0.date < $1.date })
            .map { AnalyticsData.DailyStat(date: $0.date, dateString: dfShort.string(from: $0.date), fullDateString: $0.full, screenshotsCount: $0.sc, textCount: $0.tc) }

        // 2. 每小时分布 (Hourly 0..23)
        var hourlyScreenshots = Array(repeating: 0, count: 24)
        var hourlyText = Array(repeating: 0, count: 24)

        for r in allRecords {
            let h = calendar.component(.hour, from: r.capturedAt)
            if h >= 0 && h < 24 { hourlyScreenshots[h] += 1 }
        }
        for c in allClips where c.kind == .text {
            let h = calendar.component(.hour, from: c.createdAt)
            if h >= 0 && h < 24 { hourlyText[h] += 1 }
        }

        var hourlyStats: [AnalyticsData.HourlyStat] = []
        var peakHour = 0
        var maxHourTotal = -1
        for h in 0..<24 {
            let stat = AnalyticsData.HourlyStat(hour: h, screenshotsCount: hourlyScreenshots[h], textCount: hourlyText[h])
            hourlyStats.append(stat)
            if stat.totalCount > maxHourTotal {
                maxHourTotal = stat.totalCount
                peakHour = h
            }
        }

        // 3. Top 来源应用统计
        var appCounts: [String: Int] = [:]
        var totalAppClips = 0
        for c in allClips {
            let app = (c.sourceApp ?? "").trimmingCharacters(in: .whitespaces)
            let name = app.isEmpty ? "未知应用" : app
            appCounts[name, default: 0] += 1
            totalAppClips += 1
        }
        for n in allNotes {
            let app = (n.sourceApp ?? "").trimmingCharacters(in: .whitespaces)
            let name = app.isEmpty ? "文字收纳" : app
            appCounts[name, default: 0] += 1
            totalAppClips += 1
        }

        let topApps = appCounts
            .sorted(by: { $0.value > $1.value })
            .prefix(8)
            .map { AnalyticsData.AppStat(
                appName: $0.key,
                count: $0.value,
                percentage: totalAppClips > 0 ? (Double($0.value) / Double(totalAppClips) * 100.0) : 0.0
            )}

        return AnalyticsData(
            totalScreenshots: allRecords.count,
            totalTextClips: allClips.filter { $0.kind == .text }.count,
            totalNotes: allNotes.count,
            todayScreenshots: todayScreenshots,
            todayTextClips: todayText,
            totalDiskBytes: totalBytes,
            peakHour: peakHour,
            dailyStats: dailyStats,
            hourlyStats: hourlyStats,
            topApps: topApps
        )
    }
}
