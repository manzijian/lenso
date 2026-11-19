import Foundation
import SQLite3

extension ScreenshotStore {

    /// 汇总桌面小组件需要的轻量数据：今日、近 7 天、今日时段、本月日历。
    /// 全部基于截图记录，不读取任何图片。
    func makeWidgetSnapshot(retentionLabel: String) -> WidgetSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOf7Days = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
        let cutoff = min(startOf7Days, monthStart)
        let monthDays = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let todayDay = calendar.component(.day, from: now)

        var recentDates: [Date] = []
        var totalCount = 0
        var storageBytes: Int64 = 0
        var lastCapture: Date?

        queue.sync {
            var dateStmt: OpaquePointer?
            let dateSQL = "SELECT captured_at FROM screenshots WHERE captured_at >= ?;"
            if sqlite3_prepare_v2(db, dateSQL, -1, &dateStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(dateStmt, 1, cutoff.timeIntervalSince1970)
                while sqlite3_step(dateStmt) == SQLITE_ROW {
                    recentDates.append(Date(timeIntervalSince1970: sqlite3_column_double(dateStmt, 0)))
                }
            }
            sqlite3_finalize(dateStmt)

            var totalStmt: OpaquePointer?
            let totalSQL = "SELECT COUNT(*), COALESCE(SUM(file_size), 0) FROM screenshots;"
            if sqlite3_prepare_v2(db, totalSQL, -1, &totalStmt, nil) == SQLITE_OK,
               sqlite3_step(totalStmt) == SQLITE_ROW {
                totalCount = Int(sqlite3_column_int64(totalStmt, 0))
                storageBytes = sqlite3_column_int64(totalStmt, 1)
            }
            sqlite3_finalize(totalStmt)

            var lastStmt: OpaquePointer?
            let lastSQL = "SELECT MAX(captured_at) FROM screenshots;"
            if sqlite3_prepare_v2(db, lastSQL, -1, &lastStmt, nil) == SQLITE_OK,
               sqlite3_step(lastStmt) == SQLITE_ROW,
               sqlite3_column_type(lastStmt, 0) != SQLITE_NULL {
                lastCapture = Date(timeIntervalSince1970: sqlite3_column_double(lastStmt, 0))
            }
            sqlite3_finalize(lastStmt)
        }

        var last7Days = Array(repeating: 0, count: 7)
        var hourly = Array(repeating: 0, count: 24)
        var monthDaily = Array(repeating: 0, count: monthDays)
        var todayDates: [Date] = []

        for date in recentDates {
            if date >= startOf7Days {
                let offset = calendar.dateComponents(
                    [.day],
                    from: startOf7Days,
                    to: calendar.startOfDay(for: date)
                ).day ?? -1
                if offset >= 0 && offset < 7 { last7Days[offset] += 1 }
            }

            if calendar.isDate(date, inSameDayAs: now) {
                let hour = calendar.component(.hour, from: date)
                if hour >= 0 && hour < 24 { hourly[hour] += 1 }
                todayDates.append(date)
            }

            if date >= monthStart {
                let day = calendar.component(.day, from: date)
                if day >= 1 && day <= monthDays { monthDaily[day - 1] += 1 }
            }
        }

        let peakHour = hourly.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0

        let sorted = todayDates.sorted()
        let averageInterval: Double? = {
            guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else { return nil }
            return last.timeIntervalSince(first) / Double(sorted.count - 1) / 60
        }()

        // 周一为第一列：weekday 1=周日 … 7=周六
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (weekday + 5) % 7

        return WidgetSnapshot(
            generatedAt: now,
            todayCount: last7Days[6],
            yesterdayCount: last7Days[5],
            last7Days: last7Days,
            hourlyToday: hourly,
            peakHour: peakHour,
            averageIntervalMinutes: averageInterval,
            monthYear: calendar.component(.year, from: now),
            monthNumber: calendar.component(.month, from: now),
            monthDays: monthDays,
            leadingBlanks: leadingBlanks,
            todayDay: todayDay,
            monthDaily: monthDaily,
            monthTotal: monthDaily.reduce(0, +),
            lastCaptureAt: lastCapture,
            storageBytes: storageBytes,
            totalCount: totalCount,
            retentionLabel: retentionLabel
        )
    }
}
