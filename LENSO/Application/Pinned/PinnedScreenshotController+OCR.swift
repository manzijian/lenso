import AppKit
import SwiftUI

// MARK: - 贴图 OCR 识别与翻译扩展

extension PinnedScreenshotController {
    func runOCR(thenTranslate: Bool = false) {
        pinnedState.ocrTask?.cancel()
        pinnedState.ocrPhase = .running
        pinnedState.ocrErrorMessage = nil
        pinnedState.ocrLines = []
        pinnedState.translations = [:]
        pinnedState.translationPhase = .idle
        pinnedState.justSavedNote = false

        let composited = imageView.renderCompositedImage()
        pinnedState.ocrTask = Task {
            do {
                let lines = try await ProviderRegistry.ocr.recognizeText(in: composited, languages: ["zh-Hans", "en-US"])
                guard !Task.isCancelled else { return }
                pinnedState.ocrLines = lines
                pinnedState.ocrPhase = lines.isEmpty ? .empty : .done
                if thenTranslate, !lines.isEmpty {
                    pinnedState.panelTab = .translate
                    runTranslation()
                }
            } catch {
                guard !Task.isCancelled else { return }
                pinnedState.ocrPhase = .failed
                pinnedState.ocrErrorMessage = error.localizedDescription
            }
        }
    }

    func runTranslation() {
        pinnedState.panelTab = .translate
        if pinnedState.ocrLines.isEmpty {
            runOCR(thenTranslate: true)
            return
        }
        translateLines()
    }

    func translateLines() {
        pinnedState.translationTask?.cancel()
        pinnedState.translationPhase = .running
        pinnedState.translationErrorMessage = nil
        let lines = pinnedState.ocrLines
        pinnedState.translationTask = Task {
            var results: [UUID: String] = [:]
            var firstError: String?
            for line in lines {
                guard !Task.isCancelled else { return }
                do {
                    let target = ProviderRegistry.translation.defaultTargetLanguage(for: line.text)
                    let translated = try await ProviderRegistry.translation.translate(line.text, from: nil, to: target)
                    results[line.id] = translated
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                    results[line.id] = ""
                }
            }
            guard !Task.isCancelled else { return }
            pinnedState.translations = results
            if let firstError, results.values.allSatisfy({ $0.isEmpty }) {
                pinnedState.translationPhase = .failed
                pinnedState.translationErrorMessage = firstError
            } else {
                pinnedState.translationPhase = .done
                pinnedState.translationErrorMessage = nil
            }
        }
    }

    func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ClipboardMonitor.shared.markSelfWrite()
        SaveToastController.shared.show(
            title: "已复制文本",
            subtitle: String(text.prefix(35)) + (text.count > 35 ? "..." : ""),
            thumbnail: nil
        )
    }

    func saveOCRToNotes() {
        let content = pinnedState.ocrLines.map(\.text).joined(separator: "\n")
        guard !content.isEmpty else { return }
        do {
            _ = try ScreenshotStore.shared.createTextNote(content: content, sourceApp: "lenso 贴图识别")
            pinnedState.justSavedNote = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                pinnedState.justSavedNote = false
            }
        } catch {
            pinnedState.ocrErrorMessage = "存入失败：\(error.localizedDescription)"
        }
    }
}
