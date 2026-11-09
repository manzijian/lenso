import AppKit
import Carbon.HIToolbox
import OSLog

private let hotKeyLog = Logger(subsystem: "com.lenso.app", category: "hotkey")

/// 系统级全局快捷键：注册到 Carbon 的热键表，任何 App 在前台都能触发。
///
/// 为什么不用 SwiftUI 的 `.keyboardShortcut`：那只是本 App 处于前台时的菜单
/// 快捷键，切到别的 App 就失灵——截图工具最需要的恰恰是「随时能按」。
/// Carbon 的 `RegisterEventHotKey` 是系统级注册，且不需要辅助功能权限。
///
/// 触发后不自己实现动作，而是转成对主菜单对应菜单项的 `sendAction`：
/// 菜单项和全局热键共用同一份实现，改一处两边同时生效。
@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    /// 'LSOH'
    private static let signature: OSType = OSType(0x4C534F48)

    private var refs: [ShortcutAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    private init() {}

    // MARK: - 注册

    /// 按当前配置重新注册全部全局热键。设置里改了快捷键就调这个。
    func refresh(using store: ShortcutStore) {
        unregisterAll()
        installEventHandlerIfNeeded()
        for action in ShortcutAction.allCases {
            let combo = store.combo(for: action)
            register(action: action, combo: combo)
        }
        hotKeyLog.info("registered \(self.refs.count) global hotkey(s)")
    }

    /// 装一个全局事件处理器，接收 kEventHotKeyPressed。
    /// Carbon 的 Swift 接口不提供「注册热键时带回调」的重载，
    /// 只能自己 InstallEventHandler，然后在回调里取热键 ID。
    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let count = MemoryLayout<EventHotKeyID>.size
                let got = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    count,
                    nil,
                    &hotKeyID
                )
                guard got == noErr else { return noErr }
                // 热键回调走主线程，直接跳回 MainActor 是安全的。
                MainActor.assumeIsolated {
                    GlobalHotKeyManager.shared.handle(hotKeyID)
                }
                return noErr
            },
            1,
            &spec,
            &eventHandler,
            nil
        )
        if status != noErr {
            hotKeyLog.error("InstallEventHandler failed status=\(status)")
            eventHandler = nil
        }
    }

    private func register(action: ShortcutAction, combo: ShortcutCombo) {
        guard let keyCode = combo.carbonKeyCode else {
            hotKeyLog.error("no carbon key code for \(action.rawValue, privacy: .public) key=\(combo.key, privacy: .public)")
            return
        }
        let index = ShortcutAction.allCases.firstIndex(of: action) ?? 0
        var hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(index))
        var ref: EventHotKeyRef?
        let status = RegisterEventKeyLocked(
            keyCode: keyCode,
            modifiers: combo.carbonModifiers,
            hotKeyID: &hotKeyID,
            ref: &ref
        )
        guard status == noErr, let ref else {
            hotKeyLog.error("RegisterEventHotKey failed for \(action.rawValue, privacy: .public) status=\(status)")
            return
        }
        refs[action] = ref
    }

    /// 包一层：Carbon 的 RegisterEventHotKey 要 EventTargetRef 与 OptionBits。
    private func RegisterEventKeyLocked(
        keyCode: UInt32,
        modifiers: UInt32,
        hotKeyID: inout EventHotKeyID,
        ref: inout EventHotKeyRef?
    ) -> OSStatus {
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
    }

    private func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    // MARK: - 触发

    private func handle(_ hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == Self.signature else { return }
        let index = Int(hotKeyID.id)
        guard ShortcutAction.allCases.indices.contains(index) else { return }
        let action = ShortcutAction.allCases[index]
        hotKeyLog.info("global hotkey fired: \(action.rawValue, privacy: .public)")
        NSApp.activate(ignoringOtherApps: true)
        guard let item = Self.findMenuItem(titled: action.menuTitle) else {
            hotKeyLog.error("menu item not found for \(action.rawValue, privacy: .public)")
            return
        }
        guard let selector = item.action else { return }
        NSApp.sendAction(selector, to: item.target, from: item)
    }

    /// 在主菜单里按标题找菜单项（递归子菜单）。
    private static func findMenuItem(titled title: String) -> NSMenuItem? {
        guard let main = NSApp.mainMenu else { return nil }
        return search(main, title: title)
    }

    private static func search(_ menu: NSMenu, title: String) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title { return item }
            if let submenu = item.submenu, let found = search(submenu, title: title) {
                return found
            }
        }
        return nil
    }
}

// MARK: - ShortcutCombo 的 Carbon 映射

/// Carbon 键码映射放在单独文件里：Carbon.HIToolbox 的 `Event` / `EventModifiers`
/// 与 SwiftUI 的同名类型冲突，同一个文件里不能同时 import。
extension ShortcutCombo {
    // MARK: - Carbon（系统级全局热键）

    /// Carbon 修饰键位。
    var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0
        if command { modifiers |= UInt32(cmdKey) }
        if shift { modifiers |= UInt32(shiftKey) }
        if option { modifiers |= UInt32(optionKey) }
        if control { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    /// Carbon 虚拟键码，用于 RegisterEventHotKey。
    ///
    /// 键名是 SwiftUI 那一套（"1"、"p"、","、"space"…），这里映射到 ANSI 键码。
    /// 拿不到对应键码时返回 nil——注册不了就不注册，不猜。
    var carbonKeyCode: UInt32? {
        switch key {
        case "space": return UInt32(kVK_Space)
        case "return": return UInt32(kVK_Return)
        case "delete": return UInt32(kVK_Delete)
        case "forwardDelete": return UInt32(kVK_ForwardDelete)
        case "escape": return UInt32(kVK_Escape)
        case "tab": return UInt32(kVK_Tab)
        case "leftArrow": return UInt32(kVK_LeftArrow)
        case "rightArrow": return UInt32(kVK_RightArrow)
        case "upArrow": return UInt32(kVK_UpArrow)
        case "downArrow": return UInt32(kVK_DownArrow)
        case "home": return UInt32(kVK_Home)
        case "end": return UInt32(kVK_End)
        case "pageUp": return UInt32(kVK_PageUp)
        case "pageDown": return UInt32(kVK_PageDown)
        default: break
        }
        // 功能键 f1…f12
        if key.hasPrefix("f"), let number = Int(key.dropFirst()), (1...12).contains(number) {
            guard let code = Self.functionKeyCodes[number] else { return nil }
            return UInt32(code)
        }
        // 单个字符：字母 / 数字 / 标点
        guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 else { return nil }
        let character = Character(scalar)
        // 表里存的是大写字母，Shift 记录的组合会带 Shift 修饰键，键本身仍是字母
        if let upper = character.uppercased().first, upper.isLetter {
            return Self.carbonCode(forCharacter: upper)
        }
        return Self.carbonCode(forCharacter: character)
    }

    /// 字母数字标点 → ANSI 虚拟键码。
    ///
    /// 注意：Carbon 的 ANSI 键码**不是** ASCII 顺序（kVK_ANSI_A=0、
    /// kVK_ANSI_1=18、kVK_ANSI_0=29…），必须查表，不能按偏移算——
    /// 按偏移算出来的是错键位，注册了也按不出来。
    private static func carbonCode(forCharacter character: Character) -> UInt32? {
        guard let code = ansiCodes[character] else { return nil }
        return UInt32(code)
    }

    /// 字符 → Carbon ANSI 键码表。
    private static let ansiCodes: [Character: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E,
        "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J,
        "K": kVK_ANSI_K, "L": kVK_ANSI_L, "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O,
        "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
        "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X, "Y": kVK_ANSI_Y,
        "Z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "-": kVK_ANSI_Minus,
        "=": kVK_ANSI_Equal, "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave
    ]

    /// f1…f12 的 Carbon 键码。
    private static let functionKeyCodes: [Int: Int] = [
        1: kVK_F1, 2: kVK_F2, 3: kVK_F3, 4: kVK_F4,
        5: kVK_F5, 6: kVK_F6, 7: kVK_F7, 8: kVK_F8,
        9: kVK_F9, 10: kVK_F10, 11: kVK_F11, 12: kVK_F12
    ]
}
