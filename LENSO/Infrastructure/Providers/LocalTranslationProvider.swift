import Foundation
import NaturalLanguage
import Translation

/// 本地翻译：系统 Translation 框架，端侧模型，不联网、不要 key。
/// 语种模型按需下载：首次译某个语种对时，系统会走一次下载流程。
/// 注意：TranslationSession 的生命周期不许跨越模型存活，
//       每次翻译新建一个 session，用完即丢。
@MainActor
struct LocalTranslationProvider: TranslationProvider {
    static let providerID = "local"

    let id = providerID
    let displayName = "本地翻译"

    func translate(_ text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }

        let sourceLanguage = source ?? detectLanguage(of: trimmed) ?? Locale.Language(identifier: "zh-Hans")
        guard sourceLanguage.identifier != target.identifier else { return trimmed }

        let session = TranslationSession(installedSource: sourceLanguage, target: target)
        switch await availability(from: sourceLanguage, to: target) {
        case .unsupported:
            throw TranslationError.unsupportedPair(source: sourceLanguage, target: target)
        case .downloadable:
            do {
                // 触发系统下载该语种对的模型（首次使用会弹系统提示）
                try await session.prepareTranslation()
            } catch {
                throw TranslationError.modelNotInstalled(source: sourceLanguage, target: target)
            }
        case .available:
            break
        }

        do {
            let response = try await session.translate(trimmed)
            return response.targetText
        } catch {
            throw TranslationError.underlying(message: error.localizedDescription)
        }
    }

    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationAvailability {
        guard source.identifier != target.identifier else { return .available }
        switch LanguageAvailability().status(from: source, to: target) {
        case .installed: return .available
        case .supported: return .downloadable
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    func detectLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let code = recognizer.dominantLanguage?.rawValue else { return nil }
        return Locale.Language(identifier: code)
    }
}
