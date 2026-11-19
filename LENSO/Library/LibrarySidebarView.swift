import SwiftUI
import AppKit

/// 图库一级与二级导航分区定义
enum LibrarySection: Hashable {
    case screenshots
    case text
    case recent
    case favorites
    case analytics
    case settings(SettingsCategory)

    var isSettings: Bool {
        if case .settings = self { return true }
        return false
    }
}

/// 图库侧边栏：展开为分区导航，收起为图标轨道（两种形态共用同一套路由）
struct LibrarySidebarView: View {
    @Binding var section: LibrarySection
    let screenshotsCount: Int
    let textCount: Int
    let recentCount: Int
    let favoritesCount: Int
    let storageBytes: Int64

    @AppStorage("librarySidebarCollapsed") private var isCollapsed = false
    @State private var isSettingsExpanded: Bool = true
    @State private var showSettingsPopover = false
    @State private var liveWidth: CGFloat = 206
    @State private var dragStartWidth: CGFloat = 206
    @State private var isResizing = false

    private var sidebarWidth: CGFloat { liveWidth }
    /// 拖拽过程中实时切换到图标轨道形态
    private var isNarrow: Bool { liveWidth < 140 }
    private let ink = Color(red: 0.16, green: 0.17, blue: 0.20)

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    if !isNarrow {
                        groupLabel("内容")
                    }

                    navItem("截图", icon: "photo.stack.fill", count: screenshotsCount, target: .screenshots)
                    navItem("文字", icon: "text.alignleft", count: textCount, target: .text)
                    navItem("最近 7 天", icon: "clock.fill", count: recentCount, target: .recent, shortTitle: "最近")
                    navItem("收藏", icon: "star.fill", count: favoritesCount, target: .favorites)

                    if !isNarrow {
                        groupLabel("洞察")
                    }

                    navItem("数据看板", icon: "chart.bar.xaxis", target: .analytics, shortTitle: "看板")

                    settingsSection
                }
                .padding(.horizontal, isCollapsed ? 10 : 10)
                .padding(.top, 2)
            }

            if !isNarrow {
                storageCard
            }
        }
        .padding(.bottom, 12)
        .frame(width: sidebarWidth)
        .overlay(alignment: .trailing) { resizeHandle }
        .onAppear {
            liveWidth = isCollapsed ? 66 : 206
        }
    }

    // MARK: - 拖拽边缘收起 / 展开

    private var resizeHandle: some View {
        Rectangle()
            .fill(isResizing ? Color.black.opacity(0.10) : Color.black.opacity(0.001))
            .frame(width: 3)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            dragStartWidth = liveWidth
                        }
                        liveWidth = min(240, max(56, dragStartWidth + value.translation.width))
                    }
                    .onEnded { _ in
                        isResizing = false
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            let collapse = liveWidth < 140
                            isCollapsed = collapse
                            liveWidth = collapse ? 66 : 206
                        }
                        dragStartWidth = liveWidth
                    }
            )
    }

    // MARK: - 顶部：品牌与折叠按钮

    private var header: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: 34)

            if isNarrow {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LensoColors.kleinBlueBright)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text("L")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white)
                    )
            } else {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LensoColors.kleinBlueBright)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Text("L")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    Text("lenso")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(ink)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, isNarrow ? 0 : 12)
        .padding(.bottom, 12)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Color.secondary.opacity(0.55))
            .padding(.horizontal, 9)
            .padding(.top, 10)
            .padding(.bottom, 3)
    }

    // MARK: - 导航项

    @ViewBuilder
    private func navItem(
        _ title: String,
        icon: String,
        count: Int? = nil,
        target: LibrarySection,
        shortTitle: String? = nil
    ) -> some View {
        let isActive = section == target

        if isNarrow {
            Button {
                section = target
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: isActive ? .semibold : .medium))
                    Text(shortTitle ?? title)
                        .font(.system(size: 8.5, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                }
                .foregroundStyle(isActive ? .white : ink)
                .frame(width: 46, height: 44)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LensoColors.kleinBlueBright)
                            .shadow(color: LensoColors.kleinBlueBright.opacity(0.26), radius: 5, y: 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 0)
            .help(title)
        } else {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? .white : ink)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? .white : ink)

                Spacer(minLength: 0)

                if let count {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: isActive ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isActive ? LensoColors.kleinBlueBright : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(isActive ? Color.white : Color.black.opacity(0.04))
                        )
                }
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
            .onTapGesture { section = target }
        }
    }

    // MARK: - 设置

    @ViewBuilder
    private var settingsSection: some View {
        if isNarrow {
            Button {
                showSettingsPopover.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: section.isSettings ? .semibold : .medium))
                    .foregroundStyle(section.isSettings ? .white : ink)
                    .frame(width: 46, height: 44)
                    .background {
                        if section.isSettings {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(LensoColors.kleinBlueBright)
                                .shadow(color: LensoColors.kleinBlueBright.opacity(0.26), radius: 5, y: 2)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .help("设置")
            .popover(isPresented: $showSettingsPopover, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("设置")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)

                    ForEach(SettingsCategory.allCases) { cat in
                        let isActive = section == .settings(cat)
                        Button {
                            section = .settings(cat)
                            showSettingsPopover = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 16)
                                Text(cat.rawValue)
                                    .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                                Spacer(minLength: 0)
                                if isActive {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .foregroundStyle(isActive ? LensoColors.kleinBlueBright : ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isActive ? LensoColors.kleinBlueSoft : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .frame(width: 168)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)

                HStack(spacing: 9) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12.5, weight: section.isSettings ? .semibold : .medium))
                        .foregroundStyle(section.isSettings && !isSettingsExpanded ? .white : (section.isSettings ? LensoColors.kleinBlueBright : ink))
                        .frame(width: 18)

                    Text("设置")
                        .font(.system(size: 12.5, weight: section.isSettings ? .semibold : .medium))
                        .foregroundStyle(section.isSettings && !isSettingsExpanded ? .white : ink)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(section.isSettings && !isSettingsExpanded ? Color.white.opacity(0.9) : Color.secondary.opacity(0.7))
                        .rotationEffect(.degrees(isSettingsExpanded ? 90 : 0))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                isSettingsExpanded.toggle()
                            }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    if section.isSettings && !isSettingsExpanded {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LensoColors.kleinBlueBright)
                            .shadow(color: LensoColors.kleinBlueBright.opacity(0.28), radius: 6, y: 2)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isSettingsExpanded = true
                        if !section.isSettings {
                            section = .settings(.general)
                        }
                    }
                }

                if isSettingsExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(SettingsCategory.allCases) { cat in
                            let isActive = section == .settings(cat)
                            HStack(spacing: 8) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 10.5, weight: isActive ? .semibold : .medium))
                                    .foregroundStyle(isActive ? .white : Color.secondary)
                                    .frame(width: 16)

                                Text(cat.rawValue)
                                    .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                                    .foregroundStyle(isActive ? .white : Color(red: 0.22, green: 0.22, blue: 0.26))

                                Spacer()
                            }
                            .padding(.leading, 24)
                            .padding(.trailing, 10)
                            .padding(.vertical, 5)
                            .background {
                                if isActive {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(LensoColors.kleinBlueBright)
                                        .shadow(color: LensoColors.kleinBlueBright.opacity(0.24), radius: 4, y: 1)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                section = .settings(cat)
                            }
                        }
                    }
                    .padding(.top, 1)
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - 存储状态

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text("存储占用")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.75))
                Spacer()
                Text(byteText)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ink.opacity(0.7))
            }

            HStack(spacing: 5) {
                Text("\(screenshotsCount) 张截图")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.025))
        )
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private var byteText: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }
}
