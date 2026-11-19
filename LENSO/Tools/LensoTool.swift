import SwiftUI
import Observation

/// 内置工具元数据。
/// 工具随 App 一起编译发布（内置插件化），不做外部脚本安装，
/// 安装/停用只影响「是否出现在状态栏面板与工作台入口」。
struct LensoToolDescriptor: Identifiable, Hashable, Sendable {
    enum Availability: String, Sendable {
        /// 当前版本已实现，可安装、可打开
        case available
        /// 目录中预留，按钮置灰，避免给出假功能
        case comingSoon
    }

    let id: String
    let name: String
    let summary: String
    let symbol: String
    let version: String
    let sizeText: String
    let group: String
    let availability: Availability
    /// 截图内核不可卸载
    let isCore: Bool

    var isAvailable: Bool { availability == .available }
}

/// 工具注册表：单一数据源，持久化到 UserDefaults。
/// 只保存 id 列表，不持有任何视图或资源，启动开销接近零。
@Observable
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()

    private static let installedKey = "lenso.tools.installed.v1"
    private static let disabledKey = "lenso.tools.disabled.v1"

    /// 工具目录固定顺序（含不可卸载的截图内核）
    static let catalog: [LensoToolDescriptor] = [
        LensoToolDescriptor(
            id: "capture", name: "区域截图", summary: "框选屏幕任意区域，支持标注与贴图",
            symbol: "viewfinder", version: "v2.0", sizeText: "内核",
            group: "内核", availability: .available, isCore: true
        ),
        LensoToolDescriptor(
            id: "json", name: "JSON 格式化", summary: "美化、压缩与校验，在独立工作台中编辑",
            symbol: "curlybraces", version: "v1.2", sizeText: "0.9 MB",
            group: "开发", availability: .available, isCore: false
        ),
        LensoToolDescriptor(
            id: "regex", name: "正则测试", summary: "实时匹配、替换与捕获组预览",
            symbol: "asterisk", version: "v1.1", sizeText: "0.6 MB",
            group: "开发", availability: .available, isCore: false
        ),
    ]

    private let defaults: UserDefaults

    /// 已安装工具 id（按安装顺序展示）
    private(set) var installedIDs: [String]
    /// 已安装但被单独停用的工具 id
    private(set) var disabledIDs: Set<String>

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let known = Set(Self.catalog.map(\.id))
        if let saved = defaults.array(forKey: Self.installedKey) as? [String] {
            installedIDs = saved.filter { known.contains($0) && $0 != "capture" }
        } else {
            // 首次启动：预装两个开发工具
            installedIDs = ["json", "regex"]
        }
        disabledIDs = Set(defaults.stringArray(forKey: Self.disabledKey) ?? [])
        persist()
    }

    // MARK: - 查询

    /// 状态栏面板里真正可用的工具：已安装 + 未停用 + 已实现
    var enabledTools: [LensoToolDescriptor] {
        installedIDs.compactMap { id in
            Self.catalog.first { $0.id == id }
        }
        .filter { $0.isAvailable && !disabledIDs.contains($0.id) }
    }

    var installedCount: Int {
        installedIDs.filter { id in Self.catalog.first { $0.id == id }?.isAvailable == true }.count
    }

    func descriptor(for id: String) -> LensoToolDescriptor? {
        Self.catalog.first { $0.id == id }
    }

    func isInstalled(_ id: String) -> Bool {
        id == "capture" || installedIDs.contains(id)
    }

    func isEnabled(_ id: String) -> Bool {
        isInstalled(id) && !disabledIDs.contains(id)
    }

    // MARK: - 变更

    func install(_ id: String) {
        guard let tool = descriptor(for: id), tool.isAvailable, !tool.isCore else { return }
        guard !installedIDs.contains(id) else { return }
        installedIDs.append(id)
        disabledIDs.remove(id)
        persist()
    }

    func uninstall(_ id: String) {
        guard let tool = descriptor(for: id), !tool.isCore else { return }
        installedIDs.removeAll { $0 == id }
        disabledIDs.remove(id)
        persist()
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard !id.isEmpty else { return }
        if enabled {
            disabledIDs.remove(id)
        } else {
            disabledIDs.insert(id)
        }
        persist()
    }

    private func persist() {
        defaults.set(installedIDs, forKey: Self.installedKey)
        defaults.set(Array(disabledIDs), forKey: Self.disabledKey)
    }
}

/// 工具视图工厂：只在用户真正打开工具时创建视图，启动期零实例化。
@MainActor
enum LensoToolFactory {
    static func makeView(for tool: LensoToolDescriptor, initialText: String? = nil) -> AnyView? {
        switch tool.id {
        case "json":
            return AnyView(JSONToolView(initialText: initialText))
        case "regex":
            return AnyView(RegexToolView())
        default:
            return nil
        }
    }

    /// 各工具工作台的首选尺寸（固定初始值，避免打开时二次布局）
    static func preferredSize(for tool: LensoToolDescriptor) -> CGSize {
        switch tool.id {
        case "json": return CGSize(width: 980, height: 640)
        case "regex": return CGSize(width: 940, height: 620)
        default: return CGSize(width: 860, height: 560)
        }
    }
}

/// 工具图标底座：克莱因蓝渐变方块 + 细高光，目录与面板共用
struct LensoToolIcon: View {
    let tool: LensoToolDescriptor
    var size: CGFloat = 28

    var body: some View {
        let base = LensoColors.kleinBlueBright
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [LensoColors.kleinBlue, base],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            }
            .overlay {
                Image(systemName: tool.symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: base.opacity(0.24), radius: size * 0.18, y: 1)
    }
}
