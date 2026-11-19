import Foundation

/// 小组件唯一 kind，主 App 刷新与扩展读取都用它。
enum LensoWidgetKind {
    static let identifier = "LensoWidget"
}

/// 桌面小组件快照：只有数字与时间，不含任何图片。
/// 主 App 写入 `~/Library/Application Support/LENSO/widget-snapshot.json`，
/// 小组件扩展在时间线刷新时读取同一个文件。
struct WidgetSnapshot: Codable, Sendable {
    var generatedAt: Date

    // 今日
    var todayCount: Int
    var yesterdayCount: Int
    var last7Days: [Int]          // 最早 → 今天（最后一个元素是今天）
    var hourlyToday: [Int]        // 0..23
    var peakHour: Int
    var averageIntervalMinutes: Double?

    // 本月
    var monthYear: Int
    var monthNumber: Int
    var monthDays: Int
    var leadingBlanks: Int        // 周一为第一列，1 号前需要空出的格子数
    var todayDay: Int
    var monthDaily: [Int]         // 索引 0 对应 1 号
    var monthTotal: Int

    // 汇总
    var lastCaptureAt: Date?
    var storageBytes: Int64
    var totalCount: Int
    var retentionLabel: String

    static let empty = WidgetSnapshot(
        generatedAt: .distantPast,
        todayCount: 0,
        yesterdayCount: 0,
        last7Days: Array(repeating: 0, count: 7),
        hourlyToday: Array(repeating: 0, count: 24),
        peakHour: 0,
        averageIntervalMinutes: nil,
        monthYear: 0,
        monthNumber: 0,
        monthDays: 30,
        leadingBlanks: 0,
        todayDay: 1,
        monthDaily: Array(repeating: 0, count: 30),
        monthTotal: 0,
        lastCaptureAt: nil,
        storageBytes: 0,
        totalCount: 0,
        retentionLabel: "永久保存"
    )
}

enum WidgetSnapshotStore {
    static let widgetBundleIdentifier = "com.lenso.app.widgets"

    static var directoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LENSO", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("widget-snapshot.json")
    }

    /// 小组件扩展跑在沙盒里，只能读自己的容器；
    /// 主 App（未沙盒）额外把同一份快照镜像进它的容器。
    static var widgetContainerFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(widgetBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent("LENSO", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        try write(data, to: fileURL)
        try? write(data, to: widgetContainerFileURL)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
