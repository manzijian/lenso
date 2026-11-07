import CoreGraphics
import Foundation
import Vision

/// 本地 OCR：Vision 框架，端侧识别，不联网、不要 key。
struct VisionOCRProvider: OCRProvider {
    static let providerID = "local-vision"

    let id = providerID
    let displayName = "本地识别"

    func recognizeText(in image: CGImage, languages: [String]) async throws -> [RecognizedText] {
        // VNImageRequestHandler.perform 是同步阻塞调用，挪到后台线程跑，别卡主线程。
        // Vision 相关对象只在 detached 闭包内创建和使用；
        // 进出的只有 Sendable 的值（CGImage 进，[RecognizedText] 出）。
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = languages
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw OCRError.failed(message: error.localizedDescription)
            }

            let lines: [RecognizedText] = (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedText(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            return Self.sortReadingOrder(lines)
        }.value
    }

    /// 阅读顺序：先按行（上下），行内按列（左右）。
    /// Vision 坐标左下原点：maxY 越大越靠上；同行判定用 0.02 的容差。
    private static func sortReadingOrder(_ lines: [RecognizedText]) -> [RecognizedText] {
        lines.sorted { a, b in
            let dy = a.boundingBox.maxY - b.boundingBox.maxY
            if abs(dy) > 0.02 { return dy > 0 }
            return a.boundingBox.minX < b.boundingBox.minX
        }
    }
}
