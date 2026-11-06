import SwiftUI

/// 图库数据模型（UI 层临时模型；数据库接入后由 Domain 层 Screenshot 映射）
struct ScreenshotItem: Identifiable, Hashable {
    let id: UUID
    let appName: String
    let capturedAt: Date
    let gradientIndex: Int

    /// 占位渐变（模拟不同来源的截图内容；真实截图接入后替换为 Image 加载）
    static let placeholderGradients: [[Color]] = [
        [.blue.opacity(0.75), .cyan.opacity(0.55)],
        [.indigo.opacity(0.8), .purple.opacity(0.5)],
        [.purple.opacity(0.7), .pink.opacity(0.5)],
        [.teal.opacity(0.7), .mint.opacity(0.55)],
        [.orange.opacity(0.65), .yellow.opacity(0.5)],
        [.blue.opacity(0.6), .indigo.opacity(0.6)],
    ]

    var gradient: LinearGradient {
        let c = Self.placeholderGradients[gradientIndex % Self.placeholderGradients.count]
        return LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 图库视图模型 — 组织数据与选中状态（数据库接入后由 ScreenshotRepository 驱动）
@Observable
final class LibraryViewModel {
    var screenshots: [ScreenshotItem] = []
    var selectedIDs: Set<UUID> = []
    var searchText = ""

    init() {
        // 占位数据：40 张不同时间的截图
        let now = Date()
        screenshots = (0..<40).map { i in
            ScreenshotItem(
                id: UUID(),
                appName: ["Safari", "Xcode", "微信", "预览", "Keynote", "终端"][i % 6],
                capturedAt: now.addingTimeInterval(-Double(i) * 3600 * 3),
                gradientIndex: i
            )
        }
    }

    var selectedCount: Int { selectedIDs.count }
}
