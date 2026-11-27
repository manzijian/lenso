import SwiftUI
import AppKit

/// 状态栏快捷面板（Raycast 风）：
/// 快捷操作 → 工具 → 底部入口。
/// 入场为「液态玻璃」：固定尺寸，不做灵动岛式形变，
/// 面板自上而下揭开 + 轻模糊消散 + 行错峰。
/// 视觉与主应用一致：近白玻璃底 + 克莱因蓝强调，分组卡片承载内容。
struct MenuBarPanelView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var shortcutStore = ShortcutStore.shared
    @State private var registry = ToolRegistry.shared
    @State private var revealed = false
    @State private var showTools = false
    @State private var selectedIndex: Int? = 0
    @State private var keyMonitor: Any?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let panelWidth: CGFloat = 356

    var body: some View {
        content
            .frame(width: panelWidth)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.9), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .padding(.horizontal, 28)
                .allowsHitTesting(false)
            }
            .environment(\.colorScheme, .light)
            .onAppear {
                if reduceMotion {
                    revealed = true
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        revealed = true
                    }
                }
                if UserDefaults.standard.bool(forKey: "pendingOpenLibrary") {
                    openLibrary()
                }
                installKeyMonitor()
            }
            .onDisappear {
                removeKeyMonitor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lensoShortcutsChanged)) { _ in
                shortcutStore = ShortcutStore.shared
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPreviewForScreenshot)) { note in
                guard let id = note.object as? UUID,
                      let record = (try? ScreenshotStore.shared.list())?.first(where: { $0.id == id }),
                      let cgImage = ScreenshotStore.shared.loadImage(record) else { return }
                CaptureCoordinator.shared.pin(image: cgImage, isPreview: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLibraryOnLaunch)) { _ in
                openLibrary()
            }
    }

    // MARK: - 面板主体

    private var content: some View {
        VStack(spacing: 12) {
            let actions = allActions
            let tools = allTools

            if !actions.isEmpty {
                section(title: "快捷操作", items: actions, indexBase: 0)
            }
            if showTools && !tools.isEmpty {
                section(title: "效率工具", items: tools, indexBase: actions.count)
                    .transition(LensoTransitions.inlineExpand(reduceMotion: reduceMotion))
            }

            footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - 分组

    private func section(title: String, items: [PanelItem], indexBase: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.85))
                .padding(.leading, 6)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    let globalIndex = indexBase + offset
                    PanelRow(item: item, isSelected: selectedIndex == globalIndex) {
                        selectedIndex = globalIndex
                        activate(item)
                    }
                    .modifier(RevealEffect(revealed: revealed, index: globalIndex, reduceMotion: reduceMotion))

                    if offset < items.count - 1 {
                        Rectangle()
                            .fill(Color.black.opacity(0.05))
                            .frame(height: 0.5)
                            .padding(.leading, 50)
                            .padding(.trailing, 12)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.96))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.055), lineWidth: 0.5)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("LENSO")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.secondary.opacity(0.5))

            Spacer()

            if !allTools.isEmpty {
                footerButton(
                    showTools ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver",
                    help: showTools ? "收起工具箱" : "展开效率工具"
                ) {
                    LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                        showTools.toggle()
                    }
                }
            }
            footerButton("chart.bar.xaxis", help: "数据看板") {
                openWindow(id: "library")
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openAnalyticsSection, object: nil)
                StatusBarController.shared.hide()
            }
            footerButton("gearshape", help: "设置") {
                openWindow(id: "library")
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openSettingsFromMenu, object: nil)
                StatusBarController.shared.hide()
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func footerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        FooterIconButton(symbol: symbol, help: help, action: action)
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.953, green: 0.961, blue: 0.98))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [LensoColors.kleinBlueBright.opacity(0.07), .clear],
                        center: UnitPoint(x: 0.92, y: 0.0),
                        startRadius: 0,
                        endRadius: 300
                    )
                )
        }
    }

    // MARK: - 数据

    private var allActions: [PanelItem] {
        [
            PanelItem(
                id: "capture", title: "区域截图", subtitle: "框选屏幕任意区域",
                symbol: "viewfinder",
                shortcut: shortcutStore.combo(for: .captureRegion).displayString,
                tool: nil
            ),
            PanelItem(
                id: "search", title: "全局搜索", subtitle: "检索截图、剪贴板与文字便签",
                symbol: "magnifyingglass",
                shortcut: shortcutStore.combo(for: .globalSearch).displayString,
                tool: nil
            ),
            PanelItem(
                id: "library", title: "打开图库", subtitle: "按天归档与文字收纳",
                symbol: "square.grid.2x2",
                shortcut: shortcutStore.combo(for: .openLibrary).displayString,
                tool: nil
            ),
        ]
    }

    private var allTools: [PanelItem] {
        registry.enabledTools.map { tool in
            PanelItem(
                id: tool.id, title: tool.name, subtitle: tool.summary,
                symbol: tool.symbol, shortcut: nil, tool: tool
            )
        }
    }

    // MARK: - 激活

    private func activate(_ item: PanelItem) {
        if let tool = item.tool {
            ToolHostWindowController.shared.show(toolID: tool.id)
            StatusBarController.shared.hide()
            return
        }

        switch item.id {
        case "search":
            SearchPanelController.shared.show()
        case "capture":
            CaptureCoordinator.shared.startRegionCapture()
        case "library":
            openLibrary()
        default:
            break
        }
        StatusBarController.shared.hide()
    }

    private func openLibrary() {
        openWindow(id: "library")
        NSApp.activate(ignoringOtherApps: true)
        UserDefaults.standard.set(false, forKey: "pendingOpenLibrary")
    }

    // MARK: - 键盘导航

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let allItems = showTools ? (allActions + allTools) : allActions
            switch event.keyCode {
            case 53: // Esc
                StatusBarController.shared.hide()
                return nil
            case 125: // Down
                guard !allItems.isEmpty else { return nil }
                selectedIndex = ((selectedIndex ?? -1) + 1) % allItems.count
                return nil
            case 126: // Up
                guard !allItems.isEmpty else { return nil }
                selectedIndex = ((selectedIndex ?? 0) - 1 + allItems.count) % allItems.count
                return nil
            case 36, 76: // Return / Enter
                let idx = selectedIndex ?? 0
                if idx >= 0 && idx < allItems.count {
                    activate(allItems[idx])
                }
                return nil
            default:
                if let chars = event.charactersIgnoringModifiers,
                   let num = Int(chars), (1...4).contains(num) {
                    let actions = allActions
                    if num - 1 < actions.count {
                        activate(actions[num - 1])
                        return nil
                    }
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

// MARK: - 行模型

fileprivate struct PanelItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let shortcut: String?
    let tool: LensoToolDescriptor?
}

// MARK: - 行视图

private struct FooterIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? LensoColors.kleinBlueBright : .secondary)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? LensoColors.kleinBlueSoft : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(LensoPressButtonStyle(scale: 0.92))
        .onHover { hovering = $0 }
        .lensoAnimation(LensoAnimations.hover, value: hovering, reduceMotion: reduceMotion)
        .help(help)
    }
}

private struct PanelRow: View {
    let item: PanelItem
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var highlighted: Bool { hovering || isSelected }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(highlighted ? LensoColors.kleinBlueBright : Color.primary.opacity(0.92))
                    Text(item.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let shortcut = item.shortcut {
                    Keycap(text: shortcut)
                }

                if item.tool != nil {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(highlighted ? LensoColors.kleinBlueBright : Color.secondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(highlighted ? LensoColors.kleinBlueSoft : Color.clear)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LensoPressButtonStyle(scale: 0.98))
        .onHover { hovering = $0 }
        .lensoAnimation(LensoAnimations.hover, value: highlighted, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var icon: some View {
        if let tool = item.tool {
            LensoToolIcon(tool: tool, size: 28)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(highlighted ? Color.white : LensoColors.kleinBlueSoft)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(LensoColors.kleinBlueBright.opacity(0.12), lineWidth: 0.5)
                }
                .overlay {
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                }
                .frame(width: 28, height: 28)
        }
    }
}

// MARK: - 小部件

private struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(minWidth: 17, minHeight: 17)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}

private struct RevealEffect: ViewModifier {
    let revealed: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 10)
            .blur(radius: revealed || reduceMotion ? 0 : 4)
            .animation(
                reduceMotion
                    ? LensoAnimations.fade
                    : .spring(response: 0.5, dampingFraction: 0.88).delay(Double(index) * 0.034),
                value: revealed
            )
    }
}
