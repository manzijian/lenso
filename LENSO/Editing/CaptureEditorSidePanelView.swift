import AppKit
import SwiftUI

// MARK: - 截图编辑器右侧属性面板

struct CaptureEditorSidePanelView: View {
    @Binding var isSidePanelVisible: Bool
    @Binding var panelTab: PanelTab

    let ocrPhase: OCRPhase
    let ocrLines: [RecognizedText]
    let ocrErrorMessage: String?

    let translationPhase: TranslationPhase
    let translations: [UUID: String]
    let translationErrorMessage: String?

    let justSavedNote: Bool

    let onRunOCR: () -> Void
    let onRunTranslation: () -> Void
    let onCopyText: (String) -> Void
    let onSaveOCRToNotes: () -> Void

    @State private var ocrDisplayMode = 0
    @State private var translationDisplayMode = 0
    /// 结果字号，可手动放大查看
    @State private var textSize: CGFloat = 13
    @State private var hoveringFontSmaller = false
    @State private var hoveringFontLarger = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            // 拖动条：实际上由外层 AppKit 的透明拖动带接管，这里只画抓手
            HStack {
                Spacer()
                Capsule()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 34, height: 4)
                Spacer()
            }
            .frame(height: 14)
            .help("按住拖动面板")

            // 工具行：翻译 / OCR / 字号 / 关闭
            HStack(spacing: 12) {
                SideTool(icon: "character.bubble", label: "翻译", active: panelTab == .translate) {
                    LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                        if panelTab == .translate {
                            isSidePanelVisible = false
                        } else {
                            panelTab = .translate
                            if translationPhase == .idle || translationPhase == .failed {
                                onRunTranslation()
                            }
                        }
                    }
                }
                SideTool(icon: "doc.text.viewfinder", label: "OCR", active: panelTab == .ocr) {
                    LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                        if panelTab == .ocr {
                            isSidePanelVisible = false
                        } else {
                            panelTab = .ocr
                            if ocrPhase == .idle { onRunOCR() }
                        }
                    }
                }
                Spacer()
                fontSizeControls
                Button {
                    isSidePanelVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.primary.opacity(0.06)))
                }
                .buttonStyle(LensoPressButtonStyle(scale: 0.92))
                .help("关闭面板")
            }

            Group {
                switch panelTab {
                case .annotation, .ocr: ocrResultsView
                case .translate: translationResultsView
                }
            }
            .lensoAnimation(LensoAnimations.fade, value: panelTab, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.fade, value: ocrPhase, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.fade, value: translationPhase, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.snappy, value: ocrDisplayMode, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.snappy, value: translationDisplayMode, reduceMotion: reduceMotion)
        }
        .padding(16)
        // 面板尺寸固定，内容撑满整张卡片，拖动带才会落在卡片顶部
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.985, green: 0.988, blue: 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 20, y: 6)
    }

    // MARK: - 面板页签内容

    /// 结果区最大高度：字号放大时同步变高，方便看长文
    private var resultMaxHeight: CGFloat {
        min(420, max(240, textSize * 18))
    }

    /// 字号放大 / 缩小
    private var fontSizeControls: some View {
        HStack(spacing: 0) {
            Button {
                textSize = max(11, textSize - 1)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textSize <= 11 ? .tertiary : (hoveringFontSmaller ? .primary : .secondary))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveringFontSmaller && textSize > 11 ? Color.primary.opacity(0.06) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(textSize <= 11)
            .onHover { hoveringFontSmaller = $0 }
            .lensoAnimation(LensoAnimations.hover, value: hoveringFontSmaller, reduceMotion: reduceMotion)
            .help("缩小字号")

            Button {
                textSize = min(22, textSize + 1)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textSize >= 22 ? .tertiary : (hoveringFontLarger ? .primary : .secondary))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveringFontLarger && textSize < 22 ? Color.primary.opacity(0.06) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(textSize >= 22)
            .onHover { hoveringFontLarger = $0 }
            .lensoAnimation(LensoAnimations.hover, value: hoveringFontLarger, reduceMotion: reduceMotion)
            .help("放大字号")
        }
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.05)))
    }

    /// OCR 结果页
    private var ocrResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("识别结果")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !ocrLines.isEmpty {
                    Picker("", selection: $ocrDisplayMode) {
                        Text("全文展开").tag(0)
                        Text("逐行对照").tag(1)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .controlSize(.mini)
                }
                Spacer()
                if ocrPhase == .running { ProgressView().controlSize(.small) }
            }
            switch ocrPhase {
            case .idle:
                Text("对当前选区做文字识别（本地 Vision，不联网）。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在识别中…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            case .empty:
                Text("当前选区里没识别到文字。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            case .failed:
                Text(ocrErrorMessage ?? "识别失败")
                    .font(.system(size: 12)).foregroundStyle(.red)
                    .padding(.vertical, 12)
            case .done:
                if ocrDisplayMode == 0 {
                    ScrollView {
                        Text(ocrLines.map(\.text).joined(separator: "\n"))
                            .font(.system(size: textSize, weight: .regular))
                            .lineSpacing(4)
                            .lineLimit(nil)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.03)))
                    .frame(maxHeight: resultMaxHeight)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ocrLines) { line in
                                OCRLineRow(line: line, textSize: textSize) { onCopyText(line.text) }
                            }
                        }
                    }
                    .frame(maxHeight: resultMaxHeight)
                }
            }
            HStack(spacing: 8) {
                MiniButton(label: "重新识别") { onRunOCR() }
                MiniButton(label: "全部复制", disabled: ocrLines.isEmpty) {
                    onCopyText(ocrLines.map(\.text).joined(separator: "\n"))
                }
                MiniButton(
                    label: justSavedNote ? "已存入" : "存入收纳",
                    icon: justSavedNote ? "checkmark" : "square.and.arrow.down",
                    disabled: ocrLines.isEmpty
                ) {
                    onSaveOCRToNotes()
                }
            }
        }
    }

    /// 翻译结果页（原文 / 译文对照）
    private var translationResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("翻译结果")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !translations.isEmpty {
                    Picker("", selection: $translationDisplayMode) {
                        Text("译文全文").tag(0)
                        Text("逐行对照").tag(1)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .controlSize(.mini)
                }
                Spacer()
                if translationPhase == .running { ProgressView().controlSize(.small) }
            }
            switch translationPhase {
            case .idle:
                Group {
                    if ocrPhase == .empty {
                        Text("当前选区里没识别到可翻译的文字。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Text("把选区里的文字翻成目标语言（本地模型，不联网）。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在翻译中…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            case .failed:
                Text(translationErrorMessage ?? "翻译失败")
                    .font(.system(size: 12)).foregroundStyle(.red)
                    .padding(.vertical, 12)
            case .done:
                if translationDisplayMode == 0 {
                    ScrollView {
                        let text = ocrLines.map { translations[$0.id] ?? "" }.filter { !$0.isEmpty }.joined(separator: "\n")
                        Text(text)
                            .font(.system(size: textSize, weight: .regular))
                            .lineSpacing(4)
                            .lineLimit(nil)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.03)))
                    .frame(maxHeight: resultMaxHeight)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(ocrLines) { line in
                                TranslationLineRow(
                                    original: line.text,
                                    translated: translations[line.id] ?? "",
                                    textSize: textSize
                                ) {
                                    let translated = translations[line.id] ?? ""
                                    onCopyText(translated.isEmpty ? line.text : translated)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: resultMaxHeight)
                }
            }
            HStack(spacing: 8) {
                MiniButton(label: "重新翻译") { onRunTranslation() }
                MiniButton(label: "全部复制译文", disabled: translations.isEmpty) {
                    let text = ocrLines.map { translations[$0.id] ?? "" }.joined(separator: "\n")
                    onCopyText(text)
                }
            }
        }
    }
}
