import SwiftUI
import AppKit

/// 设置窗口 — Apple 设计风格 + 经典克莱因蓝（International Klein Blue）高对比白底搭配
struct SettingsWindowView: View {
    @State private var category: SettingsCategory = .general

    typealias Category = SettingsCategory

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

                        SettingsSectionContentView(category: category)
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
}
