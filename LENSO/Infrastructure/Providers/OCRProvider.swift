import CoreGraphics
import Foundation

/// OCR 服务商接口 —— 第三方预留口子。
/// 前期只有本地实现（VisionOCRProvider，Vision 框架，不联网、不要 key）。
/// 以后接云端 OCR 时，新写一个实现本协议的类型，在 ProviderRegistry 里注册 id 即可，
/// 调用方（编辑器）只认这个协议，一行都不用改。
protocol OCRProvider: Sendable {
    /// 服务商 id："local-vision"……
    var id: String { get }
    /// 界面展示名（前期界面不展示，留给以后）
    var displayName: String { get }

    /// 识别图片中的文字，按阅读顺序返回（上→下，同一行左→右）。
    /// 抛出的错误一律是 OCRError（Sendable，跨 actor 也安全）。
    func recognizeText(in image: CGImage, languages: [String]) async throws -> [RecognizedText]
}

/// 一行识别出的文字。
struct RecognizedText: Sendable, Identifiable {
    let id = UUID()
    let text: String
    let confidence: Float
    /// Vision 归一化包围框（左下原点，0-1）
    let boundingBox: CGRect

    init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

enum OCRError: LocalizedError, Sendable {
    case failed(message: String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}
