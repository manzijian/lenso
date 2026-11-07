import Foundation

/// 翻译服务商接口 —— 第三方预留口子。
///
/// 前期只有本地实现（LocalTranslationProvider，系统 Translation 框架，不联网、不要 key）。
/// 以后接 Gemini / DeepL / 其他第三方时，只需：
///   1. 新写一个实现本协议的类型（例如 GeminiTranslationProvider）
///   2. 在 ProviderRegistry.translationProvider(id:) 里按 id 返回它
///   3. 设置里出现切换入口（界面现在不放，保持本地）
/// 调用方（编辑器）只认这个协议，一行都不用改。
protocol TranslationProvider: Sendable {
    /// 服务商 id："local"、"gemini"……
    var id: String { get }
    /// 界面展示名（前期界面不展示，留给以后）
    var displayName: String { get }

    /// 翻译一段文本。`source` 为 nil 时自动检测语种。
    /// 抛出的错误一律是 TranslationError（Sendable，跨 actor 也安全）。
    func translate(_ text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String

    /// 指定语种对的可用状态。
    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationAvailability

    /// 检测一段文本的主要语种；检测不到返回 nil。
    func detectLanguage(of text: String) -> Locale.Language?
}

/// 目标语种的默认选择：中文内容译成英文，其他译成中文。
/// 检测不到时看字符：含 CJK 字符按中文算，否则按英文算。
extension TranslationProvider {
    func defaultTargetLanguage(for text: String) -> Locale.Language {
        if let detected = detectLanguage(of: text) {
            return detected.identifier.hasPrefix("zh")
                ? Locale.Language(identifier: "en")
                : Locale.Language(identifier: "zh-Hans")
        }
        let hasCJK = text.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
        }
        return hasCJK ? Locale.Language(identifier: "en") : Locale.Language(identifier: "zh-Hans")
    }
}

enum TranslationAvailability: Sendable {
    /// 模型已安装，直接可译
    case available
    /// 支持该语种对，但模型还没下载（首次使用会走系统下载）
    case downloadable
    /// 该语种对不支持
    case unsupported
}

enum TranslationError: LocalizedError, Sendable {
    case emptyText
    case unsupportedPair(source: Locale.Language, target: Locale.Language)
    case modelNotInstalled(source: Locale.Language, target: Locale.Language)
    case underlying(message: String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "没有可翻译的文字"
        case .unsupportedPair:
            return "这个语种组合暂不支持本地翻译"
        case .modelNotInstalled:
            return "语言模型还没下载，请到系统设置 → 通用 → 语言与地区 → 翻译语言里下载"
        case .underlying(let message):
            return message
        }
    }
}
