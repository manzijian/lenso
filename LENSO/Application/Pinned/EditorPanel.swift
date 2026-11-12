import AppKit

/// 编辑器覆盖面板：Esc 取消，滚轮缩放选区，右键取消/退回上一级
final class EditorPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func scrollWheel(with event: NSEvent) {
        NotificationCenter.default.post(name: .editorScrollWheel, object: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .editorRightClick, object: event)
    }
}
