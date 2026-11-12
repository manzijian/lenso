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

/// 图库侧边栏视图（包含看板下方铺开的偏好设置二级菜单）
struct LibrarySidebarView: View {
    @Binding var section: LibrarySection
    let screenshotsCount: Int
    let textCount: Int
    let recentCount: Int
    let favoritesCount: Int

    @State private var isSettingsExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 顶部留出 macOS 红绿灯高度
            Color.clear.frame(height: 38)

            navigationItem(
                "全部截图",
                icon: "photo.stack.fill",
                count: screenshotsCount,
                isActive: section == .screenshots
            )
            .onTapGesture { section = .screenshots }

            navigationItem(
                "文字收纳",
                icon: "text.alignleft",
                count: textCount,
                isActive: section == .text
            )
            .onTapGesture { section = .text }

            navigationItem(
                "最近",
                icon: "clock.fill",
                count: recentCount,
                isActive: section == .recent
            )
            .onTapGesture { section = .recent }

            navigationItem(
                "收藏夹",
                icon: "star.fill",
                count: favoritesCount,
                isActive: section == .favorites
            )
            .onTapGesture { section = .favorites }

            navigationItem(
                "数据看板",
                icon: "chart.bar.xaxis",
                isActive: section == .analytics
            )
            .onTapGesture { section = .analytics }

            // 看板正下方：偏好设置主项与铺开的二级菜单
            settingsMenuSection

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(width: 190)
    }

    // MARK: - 偏好设置二级菜单组

    private var settingsMenuSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 一级菜单项：偏好设置
            HStack(spacing: 9) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: section.isSettings ? .semibold : .medium))
                    .foregroundStyle(section.isSettings ? LensoColors.kleinBlueBright : Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 18)

                Text("偏好设置")
                    .font(.system(size: 13, weight: section.isSettings ? .semibold : .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))

                Spacer()

                Image(systemName: isSettingsExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if !isSettingsExpanded {
                        isSettingsExpanded = true
                        if !section.isSettings {
                            section = .settings(.general)
                        }
                    } else {
                        if !section.isSettings {
                            section = .settings(.general)
                        } else {
                            isSettingsExpanded.toggle()
                        }
                    }
                }
            }

            // 二级菜单：铺开各功能项
            if isSettingsExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsCategory.allCases) { cat in
                        let isActive = section == .settings(cat)
                        HStack(spacing: 8) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                                .foregroundStyle(isActive ? .white : Color.secondary)
                                .frame(width: 16)

                            Text(cat.rawValue)
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? .white : Color(red: 0.22, green: 0.22, blue: 0.26))

                            Spacer()
                        }
                        .padding(.leading, 24)
                        .padding(.trailing, 10)
                        .padding(.vertical, 5.5)
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - 通用导航项

    private func navigationItem(
        _ title: String,
        icon: String,
        count: Int? = nil,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .white : Color(red: 0.18, green: 0.18, blue: 0.22))
                .frame(width: 18)

            Text(title)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .white : Color(red: 0.18, green: 0.18, blue: 0.22))

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: isActive ? .bold : .medium, design: .rounded))
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
    }
}
