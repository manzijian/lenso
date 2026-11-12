import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

/// 数据自动保留时长预设（支持小时、天数与自定义）
enum RetentionPreset: String, CaseIterable, Identifiable {
    case never = "永久保存 (不自动删除)"
    case hours6 = "6 小时"
    case hours12 = "12 小时"
    case hours24 = "24 小时 (1 天)"
    case days3 = "3 天"
    case days7 = "7 天 (1 周)"
    case days14 = "14 天 (2 周)"
    case days30 = "30 天 (1 个月)"
    case days90 = "90 天 (3 个月)"
    case custom = "自定义时长..."

    var id: String { rawValue }

    var durationHours: Int? {
        switch self {
        case .never: return nil
        case .hours6: return 6
        case .hours12: return 12
        case .hours24: return 24
        case .days3: return 72
        case .days7: return 168
        case .days14: return 336
        case .days30: return 720
        case .days90: return 2160
        case .custom: return nil
        }
    }
}

enum RetentionUnit: String, CaseIterable, Identifiable {
    case hours = "小时"
    case days = "天"
    var id: String { rawValue }
}

/// 状态栏图标候选样式（精选原生无歧义、高质感图标，杜绝录屏圆点与拥挤糊块）
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case crop = "极简裁切刀锋 (设计剪辑风 · 推荐)"
    case pin = "悬浮贴图图钉 (便签置顶感)"
    case viewfinder = "轻透四角取景框 (CleanShot风)"
    case camera = "纤巧单反相机 (无框原生线框)"
    case scissors = "灵动截图剪刀 (Snip裁切)"
    case squareDashed = "选区虚线框 (Marquee选框)"
    case sparkle = "高光灵感星芒 (轻盈极简)"
    case dotScope = "精密微距准星 (四向对焦)"

    var id: String { rawValue }

    var systemSymbolName: String {
        switch self {
        case .crop: return "crop"
        case .pin: return "pin"
        case .viewfinder: return "viewfinder"
        case .camera: return "camera"
        case .scissors: return "scissors"
        case .squareDashed: return "square.dashed"
        case .sparkle: return "sparkle"
        case .dotScope: return "dot.scope"
        }
    }
}

/// 应用设置：单一数据源，全部持久化到 UserDefaults，改完立即生效。
/// 原则：设置页里的每个开关都必须真实起作用，不许出现点了没反应的假开关。
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private static let keyPrefix = "lenso.settings.v1."
    private let defaults: UserDefaults

    private enum Key: String, CaseIterable {
        case launchAtLogin
        case showMenuBarIcon
        case showPreviewAfterCapture
        case autoCopyAfterCapture
        case showFloatingPreview
        case followSystemAppearance
        case glassEffect
    }

    private static func key(_ key: Key) -> String { keyPrefix + key.rawValue }

    // MARK: - 通用

    /// 开机启动（SMAppService 注册登录项；ad-hoc 未签名包注册失败时开关自动回落，不说谎）。
    var launchAtLogin: Bool {
        didSet {
            persist(.launchAtLogin, launchAtLogin)
            applyLaunchAtLogin(from: oldValue)
        }
    }
    /// 菜单栏显示图标（关掉后菜单栏入口消失，用 Dock 图标点开图库再进设置）。
    var showMenuBarIcon: Bool {
        didSet { persist(.showMenuBarIcon, showMenuBarIcon) }
    }
    /// 截图后显示预览（保存完成后自动打开预览窗口）。
    var showPreviewAfterCapture: Bool {
        didSet { persist(.showPreviewAfterCapture, showPreviewAfterCapture) }
    }

    // MARK: - 截图

    /// 截图后自动复制到剪贴板。
    var autoCopyAfterCapture: Bool {
        didSet { persist(.autoCopyAfterCapture, autoCopyAfterCapture) }
    }
    /// 保存/复制后右下角浮出带缩略图的提示。
    var showFloatingPreview: Bool {
        didSet { persist(.showFloatingPreview, showFloatingPreview) }
    }

    // MARK: - 外观

    /// 跟随系统外观（开：不强制配色；关：锁定浅色，即现版行为）。
    var followSystemAppearance: Bool {
        didSet {
            persist(.followSystemAppearance, followSystemAppearance)
            applyAppearance()
        }
    }
    /// 玻璃材质效果（关：编辑器工具栏/面板与设置卡片改用实色材质）。
    var glassEffect: Bool {
        didSet { persist(.glassEffect, glassEffect) }
    }

    /// 状态栏图标样式（可在设置中随时切换）
    var menuBarIconStyle: MenuBarIconStyle {
        didSet {
            defaults.set(menuBarIconStyle.rawValue, forKey: Self.keyPrefix + "menuBarIconStyle")
        }
    }

    /// 贴图/预览记忆的缩放比例（放大后下次打开或打开其他照片自动保持那么大，不会太小）
    var previewScale: CGFloat {
        didSet {
            defaults.set(Double(previewScale), forKey: Self.keyPrefix + "previewScale")
        }
    }

    // MARK: - 数据保存与自动清理

    /// 数据自动保留时长预设
    var retentionPreset: RetentionPreset {
        didSet {
            defaults.set(retentionPreset.rawValue, forKey: Self.keyPrefix + "retentionPreset")
            runAutoCleanup()
        }
    }

    /// 自定义时长数值（例如 12、48、7）
    var customRetentionValue: Int {
        didSet {
            defaults.set(customRetentionValue, forKey: Self.keyPrefix + "customRetentionValue")
            if retentionPreset == .custom { runAutoCleanup() }
        }
    }

    /// 自定义时长单位（小时 / 天）
    var customRetentionUnit: RetentionUnit {
        didSet {
            defaults.set(customRetentionUnit.rawValue, forKey: Self.keyPrefix + "customRetentionUnit")
            if retentionPreset == .custom { runAutoCleanup() }
        }
    }

    /// 清理时保留已收藏的数据（防止用户星标的内容被误删）
    var preserveFavoritesOnCleanup: Bool {
        didSet {
            defaults.set(preserveFavoritesOnCleanup, forKey: Self.keyPrefix + "preserveFavoritesOnCleanup")
        }
    }

    /// 计算生效的保留小时数
    var effectiveRetentionHours: Int? {
        if retentionPreset == .never { return nil }
        if retentionPreset == .custom {
            let val = max(1, customRetentionValue)
            return customRetentionUnit == .hours ? val : val * 24
        }
        return retentionPreset.durationHours
    }

    /// 当前到期截止时间（早于该时间的数据即判定为过期）
    var retentionCutoffDate: Date? {
        guard let hours = effectiveRetentionHours else { return nil }
        return Calendar.current.date(byAdding: .hour, value: -hours, to: Date())
    }

    /// 执行一次过期数据清理
    @discardableResult
    func runAutoCleanup() -> ScreenshotStore.CleanupResult? {
        guard let cutoff = retentionCutoffDate else { return nil }
        return ScreenshotStore.shared.cleanupOlderThan(cutoff: cutoff, preserveFavorites: preserveFavoritesOnCleanup)
    }

    // MARK: - Init

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // read 是 static：@Observable 宏生成的存储属性在 init 里还没初始化完，
        // 调用实例方法会报 "self used before all stored properties are initialized"。
        launchAtLogin = Self.read(.launchAtLogin, default: false, defaults: defaults)
        showMenuBarIcon = Self.read(.showMenuBarIcon, default: true, defaults: defaults)
        showPreviewAfterCapture = Self.read(.showPreviewAfterCapture, default: false, defaults: defaults)
        autoCopyAfterCapture = Self.read(.autoCopyAfterCapture, default: true, defaults: defaults)
        showFloatingPreview = Self.read(.showFloatingPreview, default: true, defaults: defaults)
        followSystemAppearance = Self.read(.followSystemAppearance, default: false, defaults: defaults)
        glassEffect = Self.read(.glassEffect, default: true, defaults: defaults)

        let storedScale = defaults.double(forKey: Self.keyPrefix + "previewScale")
        previewScale = storedScale >= 0.2 ? CGFloat(storedScale) : 1.0

        let rawIcon = defaults.string(forKey: Self.keyPrefix + "menuBarIconStyle") ?? ""
        var loadedStyle = MenuBarIconStyle(rawValue: rawIcon) ?? .crop
        if rawIcon.isEmpty || rawIcon.contains("光圈") || rawIcon.contains("画中画") {
            loadedStyle = .crop
            defaults.set(loadedStyle.rawValue, forKey: Self.keyPrefix + "menuBarIconStyle")
        }
        menuBarIconStyle = loadedStyle

        let rawRetention = defaults.string(forKey: Self.keyPrefix + "retentionPreset") ?? ""
        retentionPreset = RetentionPreset(rawValue: rawRetention) ?? .never

        let customVal = defaults.integer(forKey: Self.keyPrefix + "customRetentionValue")
        customRetentionValue = customVal > 0 ? customVal : 7

        let rawUnit = defaults.string(forKey: Self.keyPrefix + "customRetentionUnit") ?? ""
        customRetentionUnit = RetentionUnit(rawValue: rawUnit) ?? .days

        if defaults.object(forKey: Self.keyPrefix + "preserveFavoritesOnCleanup") != nil {
            preserveFavoritesOnCleanup = defaults.bool(forKey: Self.keyPrefix + "preserveFavoritesOnCleanup")
        } else {
            preserveFavoritesOnCleanup = true
        }
        // 开机启动：按存量值静默同步一次（注册是幂等的）。
        if launchAtLogin { try? SMAppService.mainApp.register() }
        // 注意：这里不要调 applyAppearance()——SwiftUI 的 App.init() 早于
        // NSApplicationMain，NSApp 还是 nil，取 appearance 会崩。
        // 外观改由 AppDelegate.applicationDidFinishLaunching 统一应用。
    }

    // MARK: - Persistence

    private static func read(_ key: Key, default defaultValue: Bool, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: Self.key(key)) as? Bool ?? defaultValue
    }

    private func persist(_ key: Key, _ value: Bool) {
        defaults.set(value, forKey: Self.key(key))
    }

    // MARK: - Apply

    private var applyingLoginItem = false

    private func applyLaunchAtLogin(from oldValue: Bool) {
        guard !applyingLoginItem else { return }
        applyingLoginItem = true
        defer { applyingLoginItem = false }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 注册失败（如 ad-hoc 调试包未签名）：恢复旧值，开关不说谎。
            launchAtLogin = oldValue
        }
    }

    /// 跟随系统时把 NSApp.appearance 置空（系统决定）；否则锁定浅色。
    /// NSApp 在应用启动前为 nil，直接返回（启动后 AppDelegate 会再调一次）。
    func applyAppearance() {
        guard let app = NSApp else { return }
        app.appearance = followSystemAppearance ? nil : NSAppearance(named: .aqua)
    }
}

// MARK: - 跟随系统外观的配色修饰符

/// 跟随系统外观时不强制配色，否则锁定浅色（现版行为）。
/// 替代原来各窗口写死的 `.environment(\.colorScheme, .light)`。
struct FollowSystemColorSchemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if AppSettings.shared.followSystemAppearance {
            content
        } else {
            content.environment(\.colorScheme, .light)
        }
    }
}

extension View {
    func lensoColorScheme() -> some View {
        modifier(FollowSystemColorSchemeModifier())
    }
}
