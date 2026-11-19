import SwiftUI
import AppKit

/// 设置分类定义
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general = "通用"
    case capture = "截图"
    case tools = "工具"
    case shortcuts = "快捷键"
    case appearance = "外观"
    case mcp = "MCP 服务"
    case about = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .capture: "viewfinder"
        case .tools: "puzzlepiece.extension.fill"
        case .shortcuts: "keyboard.fill"
        case .appearance: "paintpalette.fill"
        case .mcp: "cpu"
        case .about: "info.circle.fill"
        }
    }
}

/// 设置项正文内容分发组件（供独立设置窗口与图库内置设置二级菜单共享）
struct SettingsSectionContentView: View {
    let category: SettingsCategory
    @State private var shortcutStore = ShortcutStore.shared
    @State private var settings = AppSettings.shared
    @State private var updater = UpdateChecker.shared

    var body: some View {
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
                    SettingToggleRow(label: "复制与保存成功后在右下角弹出提醒", subtitle: "复制文本、图片或截图保存时，在屏幕右下角显示浮动气泡反馈", isOn: $settings.showFloatingPreview)
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
                SettingToggleRow(label: "复制与保存成功后在右下角弹出提醒", subtitle: "复制文本、图片或截图保存时，在屏幕右下角显示浮动气泡反馈", isOn: $settings.showFloatingPreview)
            }

        case .tools:
            ToolCatalogView()

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
            VStack(spacing: 14) {
                settingCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 16) {
                            // 直接展示 App 真实图标，避免用 SF Symbol 拼出来的假图标
                            Image(nsImage: NSApp.applicationIconImage)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.16), radius: 8, y: 3)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("LENSO")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                    Text(aboutVersion)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(LensoColors.kleinBlueBright)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(LensoColors.kleinBlueSoft))
                                }

                                Text("截图、标注、剪贴板与文字收纳，一个本地优先的效率工具")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .layoutPriority(1)
                            Spacer()
                        }

                        Text("所有数据保存在本机，不上传云端；截图与文本可直接被 AI 工具通过 MCP 读取。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.secondary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        repoRow

                        Divider()

                        updateRow
                    }
                    .padding(16)
                }

                settingCard {
                    VStack(spacing: 0) {
                        aboutRow(icon: "crop", title: "截图与标注",
                                 detail: "区域截图、画笔/箭头/文字/马赛克标注，支持钉图与 OCR")
                        rowDivider
                        aboutRow(icon: "doc.on.clipboard", title: "剪贴板历史",
                                 detail: "自动记录复制的文字与图片，保留来源应用")
                        rowDivider
                        aboutRow(icon: "magnifyingglass", title: "全局搜索",
                                 detail: "截屏与文本混合检索，回车复制、空格预览")
                        rowDivider
                        aboutRow(icon: "cpu", title: "AI 连接（MCP）",
                                 detail: "向本地 AI 客户端提供只读检索与有限写入能力")
                    }
                }

                settingCard {
                    VStack(spacing: 0) {
                        aboutRow(icon: "folder", title: "数据位置",
                                 detail: "~/Library/Application Support/LENSO")
                        rowDivider
                        aboutRow(icon: "lock.shield", title: "隐私",
                                 detail: "无账号、无网络上传，所有内容仅存于本机")
                        rowDivider
                        aboutRow(icon: "clock.arrow.circlepath", title: "自动清理",
                                 detail: "可在「存储」中设置保留天数，收藏内容默认保留")
                    }
                }

                Text("© 2026 LENSO · 为 macOS 打造")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .padding(.bottom, 8)
            }
        }
    }

    private var aboutVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return "v\(version)"
    }

    // MARK: - 检查更新

    private static let repoURL = URL(string: "https://github.com/manzijian/lenso")!

    private var repoRow: some View {
        Button {
            NSWorkspace.shared.open(Self.repoURL)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LensoColors.kleinBlueBright)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(LensoColors.kleinBlueSoft))

                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub 仓库")
                        .font(.system(size: 12, weight: .medium))
                    Text("github.com/manzijian/lenso")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LensoColors.kleinBlueBright)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("在浏览器中打开 GitHub 仓库")
    }

    private var updateRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LensoColors.kleinBlueBright)
                .frame(width: 24, height: 24)
                .background(Circle().fill(LensoColors.kleinBlueSoft))

            VStack(alignment: .leading, spacing: 2) {
                Text("软件更新")
                    .font(.system(size: 12, weight: .medium))
                Text(updateSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            updateAction
        }
    }

    private var updateSubtitle: String {
        switch updater.status {
        case .idle:
            "更新来自 GitHub Releases"
        case .checking:
            "正在连接 GitHub…"
        case .upToDate:
            "当前已是最新版本"
        case .updateAvailable(let version, _):
            "发现新版本 v\(version)"
        case .failed:
            "暂时无法检查更新"
        }
    }

    @ViewBuilder
    private var updateAction: some View {
        switch updater.status {
        case .idle:
            updateButton("检查更新") {
                Task { await updater.check() }
            }
        case .checking:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("检查中")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("已是最新")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(LensoColors.kleinBlueBright)
        case .updateAvailable(_, let url):
            updateButton("前往更新") {
                updater.openRelease(url)
            }
        case .failed:
            updateButton("重试") {
                Task { await updater.check() }
            }
        }
    }

    private func updateButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LensoColors.kleinBlueBright)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(LensoColors.kleinBlueSoft))
        }
        .buttonStyle(.plain)
    }

    private func aboutRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(LensoColors.kleinBlueBright)
                .frame(width: 26, height: 26)
                .background(Circle().fill(LensoColors.kleinBlueSoft))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
