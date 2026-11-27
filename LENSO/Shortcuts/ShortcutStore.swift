import Foundation
import Observation

extension Notification.Name {
    /// 快捷键配置变化（设置里改了 / 恢复默认）
    static let lensoShortcutsChanged = Notification.Name("com.lenso.shortcutsChanged")
}

/// 快捷键配置的单一数据源：读取 / 修改 / 持久化到 UserDefaults。
@Observable
@MainActor
final class ShortcutStore {
    static let shared = ShortcutStore()

    private static let storageKey = "lenso.shortcuts.v1"

    /// 当前生效的组合。`@Observable` 会在修改后驱动 SwiftUI 刷新。
    private var combos: [ShortcutAction: ShortcutCombo]

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.combos = Self.load(from: defaults)
    }

    func combo(for action: ShortcutAction) -> ShortcutCombo {
        combos[action] ?? .defaultCombo(for: action)
    }

    /// 设置快捷键。无修饰键或与其它动作冲突时返回 false，不修改配置。
    @discardableResult
    func set(_ combo: ShortcutCombo, for action: ShortcutAction) -> Bool {
        guard combo.hasModifier else { return false }
        guard conflict(for: combo, excluding: action) == nil else { return false }
        combos[action] = combo
        persist()
        notifyChanged()
        return true
    }

    /// 强制设置快捷键并替换冲突动作（将其切回原快捷键或默认快捷键）。
    func replaceConflict(_ combo: ShortcutCombo, for action: ShortcutAction, replacing other: ShortcutAction) {
        guard combo.hasModifier else { return }
        let previous = self.combo(for: action)
        combos[action] = combo
        if previous != combo {
            combos[other] = previous
        } else {
            combos[other] = .defaultCombo(for: other)
        }
        persist()
        notifyChanged()
    }

    /// 返回已经占用该组合的其它动作。
    func conflict(for comboCandidate: ShortcutCombo, excluding action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { candidate in
            candidate != action && combo(for: candidate) == comboCandidate
        }
    }

    func reset(_ action: ShortcutAction) {
        combos[action] = .defaultCombo(for: action)
        persist()
        notifyChanged()
    }

    func resetAll() {
        combos = Dictionary(
            uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, ShortcutCombo.defaultCombo(for: $0)) }
        )
        notifyChanged()
        persist()
    }

    // MARK: - Persistence

    /// 快捷键变了：通知全局热键管理器重新注册。
    private func notifyChanged() {
        NotificationCenter.default.post(name: .lensoShortcutsChanged, object: nil)
    }

    private func persist() {
        // String 键保证 JSON 编码为对象，且对旧版本缺失的动作更宽容。
        let encodable = Dictionary(uniqueKeysWithValues: combos.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [ShortcutAction: ShortcutCombo] {
        var result = Dictionary(
            uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, ShortcutCombo.defaultCombo(for: $0)) }
        )

        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([String: ShortcutCombo].self, from: data) else {
            return result
        }

        for (rawAction, combo) in stored {
            guard let action = ShortcutAction(rawValue: rawAction), combo.hasModifier else { continue }
            result[action] = combo
        }
        return result
    }
}
