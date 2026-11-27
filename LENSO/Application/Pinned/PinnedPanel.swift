import AppKit

/// 贴图/预览浮动面板：支持 Esc、⌘W 一键彻底关闭，空格切换工具栏，响应键盘事件
final class PinnedPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onSpace: (() -> Void)?
    var onKeyCommand: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if onKeyCommand?(event) == true {
            return
        }
        if event.keyCode == 53 { // Esc 键
            onCancel?()
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "w" { // ⌘W
            onCancel?()
            return
        }
        if event.keyCode == 49 { // 空格键切换底部编辑栏
            onSpace?()
            return
        }
        super.keyDown(with: event)
    }
}
