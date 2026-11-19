import AppKit

/// 编辑器覆盖面板：Esc 取消，右键取消/退回上一级。
/// 注意：滚轮不再改变选区大小——截完图后尺寸只通过拖手柄调整，避免误触缩放。
final class EditorPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .editorRightClick, object: event)
    }
}
