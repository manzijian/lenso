import AppKit
import SwiftUI

// MARK: - 截图编辑器右侧属性面板

struct CaptureEditorSidePanelView: View {
    @Bindable var state: AnnotationState
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
    let onQuickCopy: () -> Void

    @State private var ocrDisplayMode = 0
    @State private var translationDisplayMode = 0

    var body: some View {
        VStack(spacing: 14) {
            // 顶部工具行：标注 / 翻译 / OCR / 关闭
            HStack(spacing: 16) {
                SideTool(icon: "highlighter", label: "标注", active: panelTab == .annotation) {
                    panelTab = .annotation
                    state.activeKind = .brush
                }
                SideTool(icon: "character.bubble", label: "翻译", active: panelTab == .translate) {
                    onRunTranslation()
                }
                SideTool(icon: "doc.text.viewfinder", label: "OCR", active: panelTab == .ocr) {
                    if ocrPhase == .idle { onRunOCR() } else { panelTab = .ocr }
                }
                Spacer()
                Button {
                    isSidePanelVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("关闭面板")
            }

            switch panelTab {
            case .annotation: annotationControls
            case .ocr: ocrResultsView
            case .translate: translationResultsView
            }
        }
        .padding(16)
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

    /// 标注页：颜色盘 + 粗细 + 形状快捷 + 开关 + 复制（原面板内容，原样搬过来）
    private var annotationControls: some View {
        Group {
            // 颜色盘（7 色，选中蓝圈）
            HStack(spacing: 12) {
                ForEach(0..<AnnotationPalette.count, id: \.self) { i in
                    Circle()
                        .fill(AnnotationPalette[i])
                        .frame(width: 22, height: 22)
                        .overlay {
                            if state.colorIndex == i {
                                Circle().strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2.5)
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .onTapGesture { state.colorIndex = i }
                }
            }

            // 粗细滑杆 + Npx
            HStack(spacing: 10) {
                Slider(value: $state.strokeWidth, in: 1...10, step: 1)
                    .tint(Color(nsColor: .controlAccentColor))
                Text("\(Int(state.strokeWidth))px")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
            }

            // 形状快捷行：直线/箭头/矩形/椭圆/上箭头
            HStack(spacing: 22) {
                ShapeQuick(icon: "line.diagonal", kind: .brush, state: state) { state.activeKind = .brush }
                ShapeQuick(icon: "arrow.right", kind: .arrow, state: state) { state.activeKind = .arrow }
                ShapeQuick(icon: "rectangle", kind: .rect, state: state) { state.activeKind = .rect }
                ShapeQuick(icon: "circle", kind: .ellipse, state: state) { state.activeKind = .ellipse }
                ShapeQuick(icon: "arrow.up.right", kind: .arrow, state: state) { state.activeKind = .arrow }
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.04)))

            // 马赛克 / 高亮 开关行
            ToggleRow(icon: "square.grid.3x3.square", label: "马赛克", isOn: $state.mosaicEnabled) {
                if state.mosaicEnabled { state.activeKind = .mosaic }
            }
            ToggleRow(icon: "drop", label: "高亮", isOn: $state.highlightEnabled) {
                if state.highlightEnabled { state.activeKind = .highlight }
            }

            // 复制到剪贴板（整宽按钮）
            Button {
                onQuickCopy()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("复制到剪贴板").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("⌘C").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.05)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// OCR 结果页
    private var ocrResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("识别结果").font(.system(size: 13, weight: .semibold))
                if !ocrLines.isEmpty {
                    Picker("", selection: $ocrDisplayMode) {
                        Text("全文展开").tag(0)
                        Text("逐行对照").tag(1)
                    }
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
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在识别中…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            case .empty:
                Text("当前选区里没识别到文字。").font(.system(size: 12)).foregroundStyle(.secondary)
            case .failed:
                Text(ocrErrorMessage ?? "识别失败").font(.system(size: 12)).foregroundStyle(.red)
            case .done:
                if ocrDisplayMode == 0 {
                    ScrollView {
                        Text(ocrLines.map(\.text).joined(separator: "\n"))
                            .font(.system(size: 13, weight: .regular))
                            .lineSpacing(4)
                            .lineLimit(nil)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.03)))
                    .frame(maxHeight: 280)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ocrLines) { line in
                                OCRLineRow(line: line) { onCopyText(line.text) }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            HStack(spacing: 8) {
                MiniButton(label: "重新识别") { onRunOCR() }
                MiniButton(label: "全部复制", disabled: ocrLines.isEmpty) {
                    onCopyText(ocrLines.map(\.text).joined(separator: "\n"))
                }
                MiniButton(label: justSavedNote ? "已存入" : "存入收纳", disabled: ocrLines.isEmpty) {
                    onSaveOCRToNotes()
                }
            }
        }
    }

    /// 翻译结果页（原文 / 译文对照）
    private var translationResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("翻译结果").font(.system(size: 13, weight: .semibold))
                if !translations.isEmpty {
                    Picker("", selection: $translationDisplayMode) {
                        Text("译文全文").tag(0)
                        Text("逐行对照").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .controlSize(.mini)
                }
                Spacer()
                if translationPhase == .running { ProgressView().controlSize(.small) }
            }
            switch translationPhase {
            case .idle:
                Text("把选区里的文字翻成目标语言（本地模型，不联网）。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在翻译中…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            case .failed:
                Text(translationErrorMessage ?? "翻译失败").font(.system(size: 12)).foregroundStyle(.red)
            case .done:
                if translationDisplayMode == 0 {
                    ScrollView {
                        let text = ocrLines.map { translations[$0.id] ?? "" }.filter { !$0.isEmpty }.joined(separator: "\n")
                        Text(text)
                            .font(.system(size: 13, weight: .regular))
                            .lineSpacing(4)
                            .lineLimit(nil)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.03)))
                    .frame(maxHeight: 280)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(ocrLines) { line in
                                TranslationLineRow(
                                    original: line.text,
                                    translated: translations[line.id] ?? ""
                                ) {
                                    let translated = translations[line.id] ?? ""
                                    onCopyText(translated.isEmpty ? line.text : translated)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
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
