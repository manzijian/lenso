import AppKit
import OSLog

/// 剪贴板监听：记录复制过的图片与文字（已复制过的内容去重，避免重复条目）
@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private let log = Logger(subsystem: "com.lenso.app", category: "clipboard")
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastImageHash: Int?
    private var lastText: String?
    /// 我们自己写回剪贴板时跳过记录
    private var skipNextChange = false

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        log.info("clipboard monitor started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 标记下一次剪贴板变化由本应用写入，无需记录
    func markSelfWrite() {
        skipNextChange = true
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if skipNextChange {
            skipNextChange = false
            return
        }

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
                log.info("recorded clipboard text (\(text.count) chars) from \(sourceApp ?? "?", privacy: .public)")
            } catch {
                log.error("save clipboard text failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 当前前台应用名称；LENSO 自己触发的复制不计来源
    private func frontmostAppName() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        return app.localizedName
    }

    private func imageFromPasteboard(_ pasteboard: NSPasteboard) -> CGImage? {
        // PNG / TIFF 常见格式
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
