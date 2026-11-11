import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

/// 状态栏图标候选样式
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case viewfinder = "极简取景框 (推荐)"
    case crop = "经典裁切标"
    case camera = "纤细相机"
    case scope = "精准对焦"
    case aperture = "镜头光圈"
    case scissors = "轻巧剪刀"

    var id: String { rawValue }

    var systemSymbolName: String {
        switch self {
        case .viewfinder: return "viewfinder"
        case .crop: return "crop"
        case .camera: return "camera"
        case .scope: return "dot.scope"
        case .aperture: return "camera.aperture"
        case .scissors: return "scissors"
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

        let rawIcon = defaults.string(forKey: Self.keyPrefix + "menuBarIconStyle") ?? ""
        menuBarIconStyle = MenuBarIconStyle(rawValue: rawIcon) ?? .viewfinder
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
