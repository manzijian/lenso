import AppKit
import CoreGraphics

// MARK: - 截图服务协议

public protocol ScreenCapturing: Sendable {
    func captureDisplayExcluding(displayID: CGDirectDisplayID, excludedWindowIDs: [CGWindowID]) async throws -> CGImage
}

// MARK: - 剪贴板写入协议

@MainActor
public protocol ClipboardWriting: AnyObject {
    func writeImage(_ image: CGImage)
    func writeText(_ text: String)
}

// MARK: - 错误展示协议

@MainActor
public protocol ErrorPresenting: AnyObject {
    func presentCaptureError(title: String, message: String, isPermission: Bool)
}

// MARK: - 默认真实实现

@MainActor
final class SystemClipboardWriter: ClipboardWriting {
    func writeImage(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        // 1. TIFF 基础数据
        if let tiff = nsImage.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)

            // 2. PNG 格式数据（关键：微信、飞书、现代浏览器与设计工具优先读取 PNG）
            if let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                pasteboard.setData(pngData, forType: .png)
            }
        }

        // 3. 原生图像对象写入（支持系统级粘贴）
        pasteboard.writeObjects([nsImage])
    }

    func writeText(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        ClipboardMonitor.shared.markSelfWrite()
    }
}

@MainActor
final class SystemErrorPresenter: ErrorPresenting {
    func presentCaptureError(title: String, message: String, isPermission: Bool) {
        // macOS 系统在缺少屏幕录制权限时会自动弹出系统级授权提醒，应用层无需再弹窗重复打扰
        if isPermission {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        _ = alert.runModal()
    }
}
