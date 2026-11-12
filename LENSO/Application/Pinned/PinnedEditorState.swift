import Foundation
import SwiftUI

@Observable
final class PinnedEditorState {
    var isSidePanelVisible = false
    var panelTab: PanelTab = .ocr
    var ocrPhase: OCRPhase = .idle
    var ocrLines: [RecognizedText] = []
    var ocrErrorMessage: String? = nil
    var translationPhase: TranslationPhase = .idle
    var translations: [UUID: String] = [:]
    var translationErrorMessage: String? = nil
    var justSavedNote: Bool = false
    @ObservationIgnored var ocrTask: Task<Void, Never>?
    @ObservationIgnored var translationTask: Task<Void, Never>?
}
