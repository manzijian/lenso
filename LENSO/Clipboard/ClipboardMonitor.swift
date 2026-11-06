import AppKit
import OSLog

/// 剪贴板监听：记录复制过的图片与文字（自动收进文字收纳）
///
/// 注意：必须防止 App Nap —— 应用在后台时系统会大幅节流主线程 Timer，
/// 导致「在别的 App 里复制，LENSO 收不到」。这里用后台队列的 DispatchSourceTimer，
/// 并持有 ProcessInfo 活动声明阻止 App Nap。
final class ClipboardMonitor: @unchecked Sendable {
    static let shared = ClipboardMonitor()

    private let log = Logger(subsystem: "com.lenso.app", category: "clipboard")
    private let queue = DispatchQueue(label: "com.lenso.clipboard", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var activity: NSObjectProtocol?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastImageHash: Int?
    private var lastText: String?
    /// 我们自己写回剪贴板时跳过记录
    private var skipNextChange = false
    private let stateLock = NSLock()

    func start() {
        queue.sync {
            guard timer == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "LENSO 剪贴板历史监听"
            )
            lastChangeCount = NSPasteboard.general.changeCount
            backfillNotesFromHistory()

            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 0.7, leeway: .milliseconds(150))
            t.setEventHandler { [weak self] in self?.poll() }
            t.resume()
            timer = t
            log.info("clipboard monitor started (app-nap disabled)")
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            if let activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
        }
    }

    /// 标记下一次剪贴板变化由本应用写入，无需记录
    func markSelfWrite() {
        stateLock.lock()
        skipNextChange = true
        lastChangeCount = NSPasteboard.general.changeCount
        stateLock.unlock()
    }

    private func poll() {
        stateLock.lock()
        let skipping = skipNextChange
        if skipping { skipNextChange = false }
        stateLock.unlock()

        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if skipping { return }

        // 来源应用：剪贴板变化时最前台的应用（LENSO 自身除外）
        let sourceApp = frontmostAppName()

        // 图片优先
        if let image = imageFromPasteboard(pasteboard) {
            let hash = image.hashValue // 粗略去重
            if hash != lastImageHash {
                lastImageHash = hash
                lastText = nil
                do {
                    _ = try ScreenshotStore.shared.saveClipboardImage(image, sourceApp: sourceApp)
                    log.info("recorded clipboard image \(image.width)x\(image.height) from \(sourceApp ?? "?", privacy: .public)")
                } catch {
                    log.error("save clipboard image failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            return
        }

        // 文字
        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty, text != lastText {
            lastText = text
            lastImageHash = nil
            do {
                _ = try ScreenshotStore.shared.saveClipboardText(text, sourceApp: sourceApp)
                // 同时自动收进「文字收纳」（内容去重）
                let existing = (try? ScreenshotStore.shared.listTextNotes()) ?? []
                if !existing.contains(where: { $0.content == text }) {
                    _ = try ScreenshotStore.shared.createTextNote(content: text, sourceApp: sourceApp)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .textNotesChanged, object: nil)
                    }
                }
                log.info("recorded clipboard text (\(text.count) chars) from \(sourceApp ?? "?", privacy: .public)")
            } catch {
                log.error("save clipboard text failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 把历史里已有的剪贴板文字补录进「文字收纳」（去重，最多 20 条）
    private func backfillNotesFromHistory() {
        let store = ScreenshotStore.shared
        let notes = (try? store.listTextNotes()) ?? []
        let existing = Set(notes.map(\.content))
        let texts = ((try? store.listClipboard(limit: 40)) ?? [])
            .filter { $0.kind == .text }
            .prefix(20)
        var added = 0
        for item in texts {
            guard let text = item.text, !existing.contains(text) else { continue }
            _ = try? store.createTextNote(content: text, sourceApp: item.sourceApp)
            added += 1
        }
        if added > 0 {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .textNotesChanged, object: nil)
            }
            log.info("backfilled \(added) notes from clipboard history")
        }
    }

    /// 当前前台应用名称；LENSO 自己触发的复制不计来源
    private func frontmostAppName() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        return app.localizedName
    }

    private func imageFromPasteboard(_ pasteboard: NSPasteboard) -> CGImage? {
        if let data = pasteboard.data(forType: .png),
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        if let data = pasteboard.data(forType: .tiff),
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        if let image = NSImage(pasteboard: pasteboard) {
            var rect = NSRect(origin: .zero, size: image.size)
            return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return nil
    }
}
