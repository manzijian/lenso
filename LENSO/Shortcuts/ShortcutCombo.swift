import AppKit
import SwiftUI

/// 单个快捷键组合：一个按键（普通字符或特殊键名）+ 修饰键。
struct ShortcutCombo: Codable, Equatable, Hashable {
    /// 小写键名，如 "1"、"p"、","，或特殊键名如 "space"、"return"、"delete"。
    let key: String
    let command: Bool
    let shift: Bool
    let option: Bool
    let control: Bool

    init(
        key: String,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// 至少需要一个修饰键，否则会导致普通输入误触。
    var hasModifier: Bool {
        command || shift || option || control
    }

    /// 形如 "⇧⌘1" 的展示文本（修饰键顺序：⌃⌥⇧⌘）。
    var displayString: String {
        var result = ""
        if control { result += "⌃" }
        if option { result += "⌥" }
        if shift { result += "⇧" }
        if command { result += "⌘" }
        result += Self.displayLabel(for: key)
        return result
    }

    /// 用于 SwiftUI `.keyboardShortcut(_:modifiers:)`。
    var keyEquivalent: KeyEquivalent {
        switch key {
        case "space": return .space
        case "return": return .return
        case "delete": return .delete
        case "forwardDelete": return .deleteForward
        case "escape": return .escape
        case "tab": return .tab
        case "leftArrow": return .leftArrow
        case "rightArrow": return .rightArrow
        case "upArrow": return .upArrow
        case "downArrow": return .downArrow
        case "home": return .home
        case "end": return .end
        case "pageUp": return .pageUp
        case "pageDown": return .pageDown
        default:
            if let functionKey = Self.functionKeyEquivalent(for: key) {
                return functionKey
            }
            return KeyEquivalent(key.first ?? " ")
        }
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        return modifiers
    }

    static func defaultCombo(for action: ShortcutAction) -> ShortcutCombo {
        switch action {
        case .captureRegion:
            ShortcutCombo(key: "1", command: true, shift: true)
        case .openLibrary:
            ShortcutCombo(key: "0", command: true)
        case .previewLatest:
            ShortcutCombo(key: "p", command: true, shift: true)
        case .globalSearch:
            ShortcutCombo(key: "k", command: true)
        case .clipboardHistory:
            ShortcutCombo(key: "v", command: true, shift: true)
        case .openSettings:
            ShortcutCombo(key: ",", command: true)
        }
    }

    // MARK: - Recording

    /// 从键盘事件创建组合。仅修饰键、或无法识别的按键返回 nil。
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let control = flags.contains(.control)

        if let specialKey = Self.specialKeyByCode[event.keyCode] {
            self.init(
                key: specialKey,
                command: command,
                shift: shift,
                option: option,
                control: control
            )
            return
        }

        // 忽略单独的修饰键（如 ⇧、⌘、⌥、⌃、fn）。
        guard !Self.modifierKeyCodes.contains(event.keyCode) else { return nil }

        guard let rawCharacters = event.charactersIgnoringModifiers, !rawCharacters.isEmpty,
              let character = rawCharacters.first else {
            return nil
        }

        // 控制字符（如无字符按键）无法作为快捷键。
        guard character.unicodeScalars.first.map({ $0.value >= 0x20 }) == true else {
            return nil
        }

        let key = Self.normalizedKey(character, shift: shift)
        guard !key.isEmpty else { return nil }

        self.init(
            key: key,
            command: command,
            shift: shift,
            option: option,
            control: control
        )
    }

    /// `charactersIgnoringModifiers` 仍会应用 Shift，需要把它还原为未按 Shift 的按键。
    private static func normalizedKey(_ character: Character, shift: Bool) -> String {
        if shift, let unshifted = shiftedToBase[character] {
            return String(unshifted)
        }
        return String(character).lowercased()
    }

    private static func displayLabel(for key: String) -> String {
        if let label = keyLabels[key] {
            return label
        }
        return key.uppercased()
    }

    private static func functionKeyEquivalent(for key: String) -> KeyEquivalent? {
        guard key.hasPrefix("f"),
              let number = Int(key.dropFirst()),
              (1...12).contains(number),
              let scalar = UnicodeScalar(0xF704 + number - 1) else {
            return nil
        }
        return KeyEquivalent(Character(scalar))
    }

    // MARK: - Key tables

    private static let specialKeyByCode: [UInt16: String] = [
        36: "return",
        48: "tab",
        49: "space",
        51: "delete",
        53: "escape",
        117: "forwardDelete",
        123: "leftArrow",
        124: "rightArrow",
        125: "downArrow",
        126: "upArrow",
        115: "home",
        119: "end",
        116: "pageUp",
        121: "pageDown",
        122: "f1",
        120: "f2",
        99: "f3",
        118: "f4",
        96: "f5",
        97: "f6",
        98: "f7",
        100: "f8",
        101: "f9",
        109: "f10",
        103: "f11",
        111: "f12"
    ]

    private static let modifierKeyCodes: Set<UInt16> = [
        54, 55, // command
        56, 60, // shift
        58, 61, // option
        59, 62, // control
        57,     // caps lock
        63      // fn
    ]

    /// 常见的 Shift 后字符 -> 基础按键，用于把 ⇧⌘1 记录为 key "1"。
    private static let shiftedToBase: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
        "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=",
        "{": "[", "}": "]", "|": "\\",
        ":": ";", "\"": "'",
        "<": ",", ">": ".", "?": "/", "~": "`"
    ]

    private static let keyLabels: [String: String] = [
        "space": "Space",
        "return": "↩",
        "delete": "⌫",
        "forwardDelete": "⌦",
        "escape": "⎋",
        "tab": "⇥",
        "leftArrow": "←",
        "rightArrow": "→",
        "upArrow": "↑",
        "downArrow": "↓",
        "home": "↖",
        "end": "↘",
        "pageUp": "⇞",
        "pageDown": "⇟",
        "f1": "F1", "f2": "F2", "f3": "F3", "f4": "F4",
        "f5": "F5", "f6": "F6", "f7": "F7", "f8": "F8",
        "f9": "F9", "f10": "F10", "f11": "F11", "f12": "F12"
    ]
}
