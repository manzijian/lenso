import Foundation

/// 服务商注册表：调用方只认接口，不认实现。
///
/// 前期：OCR 与翻译都只有本地实现。
/// 以后接第三方（Gemini 翻译、云端 OCR……）时：
///   1. 新写一个实现对应协议的类型
///   2. 在下面 `translationProvider(id:)` / `ocrProvider(id:)` 里按 id 返回它
///   3. 设置里出现切换入口（界面现在不放，保持本地）
/// 除此之外不用改任何调用代码。
@MainActor
enum ProviderRegistry {
    /// 当前 OCR 服务商（前期固定本地 Vision）
    static var ocr: any OCRProvider = VisionOCRProvider()
    /// 当前翻译服务商（前期固定本地 Translation 框架）
    static var translation: any TranslationProvider = LocalTranslationProvider()

    /// 按 id 取翻译服务商；未知 id 回落到本地（不崩溃）
    static func translationProvider(id: String) -> any TranslationProvider {
        switch id {
        case LocalTranslationProvider.providerID:
            return LocalTranslationProvider()
        // case "gemini": return GeminiTranslationProvider(apiKey: ...)
        default:
            return LocalTranslationProvider()
        }
    }

    /// 按 id 取 OCR 服务商；未知 id 回落到本地
    static func ocrProvider(id: String) -> any OCRProvider {
        switch id {
        case VisionOCRProvider.providerID:
            return VisionOCRProvider()
        default:
            return VisionOCRProvider()
        }
    }
}
