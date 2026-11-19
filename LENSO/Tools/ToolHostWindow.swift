import SwiftUI
import AppKit

/// 工具工作台窗口：单例复用，一次只保留一个工具视图。
/// 关闭窗口即释放 contentView 与 SwiftUI 视图，内存回落到基线。
@MainActor
final class ToolHostWindowController: NSObject, NSWindowDelegate {
    static let shared = ToolHostWindowController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    private override init() {
        super.init()
    }

    func show(toolID: String, initialText: String? = nil) {
        guard let tool = ToolRegistry.shared.descriptor(for: toolID),
              let root = LensoToolFactory.makeView(for: tool, initialText: initialText) else { return }

        closeAndRelease()

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
        window.setFrameAutosaveName("lenso.tool.\(tool.id)")

        let host = NSHostingView(rootView: root)
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.hostingView = host
    }

    func windowWillClose(_ notification: Notification) {
        // 关闭后立即释放工具视图，不把富文本编辑器留在内存里
        hostingView = nil
        window?.contentView = nil
        window?.delegate = nil
        window = nil
    }

    private func closeAndRelease() {
        guard let window else { return }
        window.delegate = nil
        window.orderOut(nil)
        window.contentView = nil
        hostingView = nil
        self.window = nil
    }
}
