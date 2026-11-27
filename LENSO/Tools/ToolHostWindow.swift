import SwiftUI
import AppKit

/// 工具工作台窗口：按 toolID 独立管理，互不销毁未保存输入；
/// 关闭窗口即释放对应 contentView 与 SwiftUI 视图，内存回落到基线。
@MainActor
final class ToolHostWindowController: NSObject, NSWindowDelegate {
    static let shared = ToolHostWindowController()

    private var windows: [String: NSWindow] = [:]
    private var hostingViews: [String: NSHostingView<AnyView>] = [:]

    private override init() {
        super.init()
    }

    func show(toolID: String, initialText: String? = nil) {
        if let existing = windows[toolID], initialText == nil {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let tool = ToolRegistry.shared.descriptor(for: toolID),
              let root = LensoToolFactory.makeView(for: tool, initialText: initialText) else { return }

        if let existing = windows[toolID] {
            let host = NSHostingView(rootView: root)
            existing.contentView = host
            hostingViews[toolID] = host
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let size = LensoToolFactory.preferredSize(for: tool)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = tool.name
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 680, height: 440)
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone]
        window.delegate = self

        let autosaveName = "lenso.tool.\(tool.id)"
        window.setFrameAutosaveName(autosaveName)
        if !window.setFrameUsingName(autosaveName) {
            window.center()
        }

        let host = NSHostingView(rootView: root)
        window.contentView = host

        windows[toolID] = window
        hostingViews[toolID] = host

        NSApp.activate(ignoringOtherApps: true)
        LensoWindowMotion.present(window, slideY: 8, makeKey: true)
    }

    func close(toolID: String) {
        guard let window = windows[toolID] else { return }
        LensoWindowMotion.dismiss(window, slideY: 6) { [weak self] in
            self?.release(toolID: toolID)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow,
              let toolID = windows.first(where: { $0.value === closedWindow })?.key else { return }
        release(toolID: toolID)
    }

    private func release(toolID: String) {
        hostingViews.removeValue(forKey: toolID)
        if let window = windows.removeValue(forKey: toolID) {
            window.contentView = nil
            window.delegate = nil
        }
    }
}
