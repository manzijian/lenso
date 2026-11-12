import SwiftUI
import AppKit

/// 设置窗口 — Apple 设计风格 + 经典克莱因蓝（International Klein Blue）高对比白底搭配
struct SettingsWindowView: View {
    @State private var category: Category = .general
    @State private var shortcutStore = ShortcutStore.shared
    @State private var settings = AppSettings.shared

    enum Category: String, CaseIterable, Identifiable {
        case general = "通用"
        case capture = "截图"
        case shortcuts = "快捷键"
        case appearance = "外观"
        case mcp = "MCP 服务"
        case about = "关于"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .capture: "viewfinder"
            case .shortcuts: "keyboard.fill"
            case .appearance: "paintpalette.fill"
            case .mcp: "cpu"
            case .about: "info.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .background(sidebarBackground)

            VStack(alignment: .leading, spacing: 0) {
                // 顶部留白（对齐红绿灯）
                Color.clear.frame(height: 38)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 分类大标题
                        HStack(spacing: 8) {
                            Text(category.rawValue)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.primary)
                            Spacer()
                        }
                        .padding(.top, 4)

                        content
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(mainBackground)
        }
        .frame(minWidth: 680, minHeight: 460)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .lensoColorScheme()
    }

    // MARK: - 背景（Apple 纯白质感 + 克莱因蓝微光）

    private var mainBackground: some View {
        ZStack {
            Color(red: 0.985, green: 0.988, blue: 0.995)
            RadialGradient(
                colors: [LensoColors.kleinBlueBright.opacity(0.045), .clear],
                center: UnitPoint(x: 0.95, y: 0.05),
                startRadius: 0,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }

    private var sidebarBackground: some View {
        Color.white
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.black.opacity(0.07)).frame(width: 1)
            }
            .ignoresSafeArea()
    }

    // MARK: - 侧栏导航（克莱因蓝胶囊）

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 顶部留出交通灯位置
            Color.clear.frame(height: 38)

            ForEach(Category.allCases) { c in
                let isActive = category == c
                HStack(spacing: 9) {
                    Image(systemName: c.icon)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                        .frame(width: 18)
                        .foregroundStyle(isActive ? .white : Color(red: 0.18, green: 0.18, blue: 0.22))

                    Text(c.rawValue)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? .white : Color(red: 0.18, green: 0.18, blue: 0.22))

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LensoColors.kleinBlueBright)
                            .shadow(color: LensoColors.kleinBlueBright.opacity(0.28), radius: 6, y: 2)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { category = c }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(width: 160)
    }

    // MARK: - 设置项内容区（纯白卡片 + 克莱因蓝控件）

    @ViewBuilder
    private var content: some View {
        switch category {
        case .general:
            VStack(alignment: .leading, spacing: 16) {
                settingCard {
                    SettingToggleRow(label: "开机自动启动 LENSO", subtitle: "登录系统后在后台默默运行", isOn: $settings.launchAtLogin)
                    rowDivider
                    SettingToggleRow(label: "在顶部菜单栏显示图标", subtitle: "方便随时唤出截图工具与图库", isOn: $settings.showMenuBarIcon)
                    rowDivider
                    SettingToggleRow(label: "在下方应用栏（程序坞）显示图标", subtitle: "关闭后隐藏下方图标，仅在顶部状态栏常驻（默认开启）", isOn: $settings.showInDock)
                    rowDivider
                    SettingToggleRow(label: "截图保存后打开预览窗口", subtitle: "截完图后自动打开独立无极缩放预览", isOn: $settings.showPreviewAfterCapture)
                    rowDivider
                    SettingToggleRow(label: "开启 MCP 本地服务", subtitle: "允许本地 AI Agent（Claude、Cursor 等）安全读取历史与剪贴板", isOn: $settings.enableMCPServer)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("数据保存期限与自动清理")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.85))

                    settingCard {
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("数据保存时长")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.primary.opacity(0.9))
                                    Text("达到设定时间后，后台将自动清理历史截图与剪贴板数据")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                Picker("", selection: $settings.retentionPreset) {
                                    ForEach(RetentionPreset.allCases) { p in
                                        Text(p.rawValue).tag(p)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 170)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if settings.retentionPreset == .custom {
                                rowDivider
                                HStack {
                                    Text("自定义保留时长")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.primary.opacity(0.9))
                                    Spacer()
                                    TextField("数值", value: $settings.customRetentionValue, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 60)
                                    Picker("", selection: $settings.customRetentionUnit) {
                                        ForEach(RetentionUnit.allCases) { u in
                                            Text(u.rawValue).tag(u)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 100)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }

                            rowDivider
                            SettingToggleRow(
                                label: "保留星标收藏的内容",
                                subtitle: "即使超过保存期限，已收藏的截图与文字便签也绝不会被自动删除",
                                isOn: $settings.preserveFavoritesOnCleanup
                            )

                            if settings.retentionPreset != .never {
                                rowDivider
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("即时手动触发清理")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.primary.opacity(0.8))
                                        if let cutoff = settings.retentionCutoffDate {
                                            Text("早于 \(DateFormatter.lensoFullDateTime.string(from: cutoff)) 的记录将被清除")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        if let res = settings.runAutoCleanup() {
                                            if res.totalDeleted > 0 {
                                                SaveToastController.shared.show(
                                                    title: "清理完成",
                                                    subtitle: "已删除 \(res.totalDeleted) 项过期数据",
                                                    thumbnail: nil
                                                )
                                            } else {
                                                SaveToastController.shared.show(
                                                    title: "已是最新",
                                                    subtitle: "当前暂无符合清理条件的过期记录",
                                                    thumbnail: nil
                                                )
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "trash")
                                            Text("立即清理过期数据")
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(LensoColors.kleinBlueBright)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(LensoColors.kleinBlueSoft))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                            }
                        }
                    }
                }
            }

        case .capture:
            settingCard {
                SettingToggleRow(label: "截图后自动复制到剪贴板", subtitle: "截完直接 ⌘V 粘贴使用", isOn: $settings.autoCopyAfterCapture)
                rowDivider
                SettingToggleRow(label: "显示浮动轻提示 (Toast)", subtitle: "截图保存或复制时在屏幕右上角给出反馈", isOn: $settings.showFloatingPreview)
            }

        case .shortcuts:
            VStack(alignment: .leading, spacing: 14) {
                settingCard {
                    ForEach(ShortcutAction.allCases) { action in
                        SettingShortcutRow(action: action, store: shortcutStore)
                        if action != ShortcutAction.allCases.last {
                            rowDivider
                        }
                    }
                }

                Button {
                    shortcutStore.resetAll()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("恢复默认快捷键")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(LensoColors.kleinBlueBright)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }

        case .appearance:
            VStack(alignment: .leading, spacing: 16) {
                settingCard {
                    SettingToggleRow(label: "跟随系统外观", subtitle: "自动在浅色与深色模式之间智能切换", isOn: $settings.followSystemAppearance)
                    rowDivider
                    SettingToggleRow(label: "玻璃材质磨砂效果", subtitle: "窗口与浮窗启用 macOS 细腻毛玻璃质感", isOn: $settings.glassEffect)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("状态栏图标样式")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.85))

                    settingCard {
                        ForEach(MenuBarIconStyle.allCases) { style in
                            HStack(spacing: 12) {
                                Image(systemName: style.systemSymbolName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(settings.menuBarIconStyle == style ? LensoColors.kleinBlueBright : Color.primary.opacity(0.8))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(settings.menuBarIconStyle == style ? LensoColors.kleinBlueSoft : Color.black.opacity(0.04))
                                    )

                                Text(style.rawValue)
                                    .font(.system(size: 13, weight: settings.menuBarIconStyle == style ? .semibold : .regular))
                                    .foregroundStyle(Color.primary.opacity(0.9))

                                Spacer()

                                if settings.menuBarIconStyle == style {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(LensoColors.kleinBlueBright)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                settings.menuBarIconStyle = style
                            }

                            if style != MenuBarIconStyle.allCases.last {
                                rowDivider
                            }
                        }
                    }
                }
            }

        case .mcp:
            MCPSettingsSectionView()

        case .about:
            settingCard {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [LensoColors.kleinBlueBright, LensoColors.kleinBlue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 54, height: 54)
                            .shadow(color: LensoColors.kleinBlueBright.opacity(0.35), radius: 8, y: 3)

                        Image(systemName: "crop")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("LENSO")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("v2.0")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LensoColors.kleinBlueBright)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(LensoColors.kleinBlueSoft))
                        }

                        Text("现代 macOS 原生截图、标注贴图与 OCR 文字收纳利器")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text("设计规范：克莱因蓝 + 纯白 Apple 设计风格")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary.opacity(0.8))
                    }
                }
                .padding(16)
            }
        }
    }

    private func settingCard<V: View>(@ViewBuilder content: @escaping () -> V) -> some View {
        SettingCardContainer(content: content)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 14)
            .opacity(0.6)
    }
}
