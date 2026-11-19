import Foundation

extension Notification.Name {
    /// MCP 使用记录发生变化（本进程内实时刷新用）
    static let mcpUsageLogDidChange = Notification.Name("lenso.mcpUsageLogDidChange")
}

/// MCP 调用日志：只记录工具调用、资源读取与客户端连接。
/// 追加写入 Application Support/LENSO/mcp-usage.jsonl，
/// 内存里最多保留 200 条，避免长期运行占内存。
final class MCPUsageLog: @unchecked Sendable {
    struct Entry: Codable, Identifiable, Sendable {
        let id: UUID
        let date: Date
        let method: String
        let name: String
        let client: String?
        let durationMS: Int
        let success: Bool
        let detail: String?
    }

    static let shared = MCPUsageLog()
    static let maxEntries = 200

    let fileURL: URL

    private let lock = NSLock()
    private var items: [Entry] = []

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("LENSO", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("mcp-usage.jsonl")
        items = Self.readEntries(from: fileURL)
    }

    // MARK: 读取

    func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    /// 合并磁盘上的记录（stdio 模式是独立进程，需要靠文件汇总）
    func reload() {
        let disk = Self.readEntries(from: fileURL)
        guard !disk.isEmpty else { return }

        lock.lock()
        var seen = Set(items.map(\.id))
        var merged = items
        for entry in disk where !seen.contains(entry.id) {
            merged.append(entry)
            seen.insert(entry.id)
        }
        merged.sort { $0.date > $1.date }
        if merged.count > Self.maxEntries {
            merged.removeLast(merged.count - Self.maxEntries)
        }
        items = merged
        lock.unlock()
    }

    // MARK: 写入

    func record(
        method: String,
        name: String,
        client: String?,
        durationMS: Int,
        success: Bool,
        detail: String?
    ) {
        let entry = Entry(
            id: UUID(),
            date: Date(),
            method: method,
            name: name,
            client: client,
            durationMS: durationMS,
            success: success,
            detail: detail
        )

        lock.lock()
        items.insert(entry, at: 0)
        if items.count > Self.maxEntries {
            items.removeLast(items.count - Self.maxEntries)
        }
        lock.unlock()

        append(entry)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mcpUsageLogDidChange, object: nil)
        }
    }

    func clear() {
        lock.lock()
        items.removeAll()
        lock.unlock()

        try? FileManager.default.removeItem(at: fileURL)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mcpUsageLogDidChange, object: nil)
        }
    }

    // MARK: 磁盘

    private func append(_ entry: Entry) {
        guard var data = try? Self.encoder.encode(entry) else { return }
        data.append(0x0A)

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                return
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func readEntries(from url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let lines = data.split(separator: 0x0A)
        var entries: [Entry] = []
        entries.reserveCapacity(lines.count)
        for line in lines {
            guard let entry = try? decoder.decode(Entry.self, from: Data(line)) else { continue }
            entries.append(entry)
        }
        entries.sort { $0.date > $1.date }
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        return entries
    }
}
