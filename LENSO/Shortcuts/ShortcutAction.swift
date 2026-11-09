import Foundation

/// 应用内可自定义的快捷键动作。
///
/// 每个动作对应 `LENSOApp` 菜单中的一个 `.keyboardShortcut`。
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case captureRegion
    case openLibrary
    case previewLatest
    case globalSearch
    case clipboardHistory
    case openSettings

    var id: String { rawValue }

    /// 设置窗口中展示的中文名称，也与菜单标题保持一致。
    var title: String {
        switch self {
        case .captureRegion: "区域截图"
        case .openLibrary: "打开图库"
        case .previewLatest: "预览最新截图"
        case .globalSearch: "全局搜索"
        case .clipboardHistory: "剪贴板历史"
        case .openSettings: "打开设置"
        }
    }

    /// 顶部菜单里对应的菜单项标题。
    /// 全局热键触发时按这个标题找到菜单项并执行它的动作，
    /// 这样菜单与全局热键共用同一份实现，不会各写一套逻辑跑偏。
    var menuTitle: String {
        switch self {
        case .captureRegion: "区域截图"
        case .openLibrary: "打开图库"
        case .previewLatest: "预览最新截图"
        case .globalSearch: "全局搜索"
        case .clipboardHistory: "剪贴板历史"
        case .openSettings: "打开设置"
        }
    }

    /// 设置窗口中使用的 SF Symbol。
    var icon: String {
        switch self {
        case .captureRegion: "viewfinder"
        case .openLibrary: "photo.on.rectangle"
        case .previewLatest: "eye"
        case .globalSearch: "magnifyingglass"
        case .clipboardHistory: "doc.on.clipboard"
        case .openSettings: "gearshape"
        }
    }
}
