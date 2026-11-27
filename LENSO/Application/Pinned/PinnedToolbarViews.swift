import SwiftUI
import AppKit

// MARK: - 贴图右侧属性/OCR/翻译面板视图

struct PinnedSidePanelView: View {
    @Bindable var state: AnnotationState
    @Bindable var pinnedState: PinnedEditorState
    let onRunOCR: () -> Void
    let onCopyAllOCR: () -> Void
    let onSaveOCRToNotes: () -> Void
    let onCopyText: (String) -> Void
    let onRunTranslation: () -> Void
    let onCopyAllTranslations: () -> Void
    let onQuickCopy: () -> Void
    let onClose: () -> Void

    @State private var ocrDisplayMode = 0
    @State private var translationDisplayMode = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            // 顶部工具行：标注 / 翻译 / OCR / 关闭
            HStack(spacing: 16) {
                SideTool(icon: "highlighter", label: "标注", active: pinnedState.panelTab == .annotation) {
                    if pinnedState.panelTab == .annotation {
                        onClose()
                    } else {
                        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                            pinnedState.panelTab = .annotation
                            if state.activeKind == nil {
                                state.activeKind = .brush
                            }
                        }
                    }
                }
                SideTool(icon: "character.bubble", label: "翻译", active: pinnedState.panelTab == .translate) {
                    if pinnedState.panelTab == .translate {
                        onClose()
                    } else {
                        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                            pinnedState.panelTab = .translate
                        }
                        if pinnedState.translationPhase == .idle || pinnedState.translationPhase == .failed {
                            onRunTranslation()
                        }
                    }
                }
                SideTool(icon: "doc.text.viewfinder", label: "OCR", active: pinnedState.panelTab == .ocr) {
                    if pinnedState.panelTab == .ocr {
                        onClose()
                    } else {
                        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                            pinnedState.panelTab = .ocr
                        }
                        if pinnedState.ocrPhase == .idle { onRunOCR() }
                    }
                }
                Spacer()
                Button(action: onClose) {
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
                switch pinnedState.panelTab {
                case .annotation:
                    annotationControls
                case .ocr:
                    ocrResultsView
                case .translate:
                    translationResultsView
                }
            }
            .lensoAnimation(LensoAnimations.fade, value: pinnedState.panelTab, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.fade, value: pinnedState.ocrPhase, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.fade, value: pinnedState.translationPhase, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.snappy, value: ocrDisplayMode, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.snappy, value: translationDisplayMode, reduceMotion: reduceMotion)
        }
        .padding(16)
        .frame(width: 340)
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

    private var annotationControls: some View {
        Group {
            // 颜色盘（7 色）
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

            // 形状快捷行（与 AnnotationKind 图标对齐）
            HStack(spacing: 18) {
                ForEach([AnnotationKind.brush, .arrow, .rect, .ellipse, .text], id: \.self) { kind in
                    ShapeQuick(icon: kind.icon, kind: kind, state: state) {
                        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                            state.activeKind = kind
                        }
                    }
                    .help(kind.label)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.04)))

            // 马赛克 / 高亮 开关行
            ToggleRow(icon: "square.grid.3x3.square", label: "马赛克", isOn: $state.mosaicEnabled) {
                if state.mosaicEnabled { state.activeKind = .mosaic }
            }
            ToggleRow(icon: "drop", label: "高亮", isOn: $state.highlightEnabled) {
                if state.highlightEnabled { state.activeKind = .highlight }
            }

            // 复制到剪贴板
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

    private var ocrResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("识别结果").font(.system(size: 13, weight: .semibold))
                if !pinnedState.ocrLines.isEmpty {
                    Picker("", selection: $ocrDisplayMode) {
                        Text("全文展开").tag(0)
                        Text("逐行对照").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .controlSize(.mini)
                }
                Spacer()
                if pinnedState.ocrPhase == .running { ProgressView().controlSize(.small) }
            }
            switch pinnedState.ocrPhase {
            case .idle:
                Text("对当前贴图做文字识别（本地 Vision，不联网）。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在识别中…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            case .empty:
                Text("当前贴图中没识别到文字。").font(.system(size: 12)).foregroundStyle(.secondary)
            case .failed:
                Text(pinnedState.ocrErrorMessage ?? "识别失败").font(.system(size: 12)).foregroundStyle(.red)
            case .done:
                if ocrDisplayMode == 0 {
                    ScrollView {
                        Text(pinnedState.ocrLines.map(\.text).joined(separator: "\n"))
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
                            ForEach(pinnedState.ocrLines) { line in
                                OCRLineRow(line: line) { onCopyText(line.text) }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            HStack(spacing: 8) {
                MiniButton(label: "重新识别") { onRunOCR() }
                MiniButton(label: "全部复制", disabled: pinnedState.ocrLines.isEmpty) { onCopyAllOCR() }
                MiniButton(
                    label: pinnedState.justSavedNote ? "已存入" : "存入收纳",
                    icon: pinnedState.justSavedNote ? "checkmark" : "square.and.arrow.down",
                    disabled: pinnedState.ocrLines.isEmpty
                ) { onSaveOCRToNotes() }
            }
        }
    }

    private var translationResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("翻译结果").font(.system(size: 13, weight: .semibold))
                if !pinnedState.translations.isEmpty {
                    Picker("", selection: $translationDisplayMode) {
                        Text("译文全文").tag(0)
                        Text("逐行对照").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .controlSize(.mini)
                }
                Spacer()
                if pinnedState.translationPhase == .running { ProgressView().controlSize(.small) }
            }
            switch pinnedState.translationPhase {
            case .idle:
                if pinnedState.ocrPhase == .empty {
                    Text("当前贴图中没识别到可翻译的文字。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text("把识别到的文字翻成目标语言（本地模型，不联网）。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在翻译中…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            case .failed:
                Text(pinnedState.translationErrorMessage ?? "翻译失败").font(.system(size: 12)).foregroundStyle(.red)
            case .done:
                if translationDisplayMode == 0 {
                    ScrollView {
                        let text = pinnedState.ocrLines.map { pinnedState.translations[$0.id] ?? "" }.filter { !$0.isEmpty }.joined(separator: "\n")
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
                            ForEach(pinnedState.ocrLines) { line in
                                TranslationLineRow(
                                    original: line.text,
                                    translated: pinnedState.translations[line.id] ?? ""
                                ) {
                                    let translated = pinnedState.translations[line.id] ?? ""
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
                MiniButton(label: "全部复制译文", disabled: pinnedState.translations.isEmpty) { onCopyAllTranslations() }
            }
        }
    }
}

// MARK: - 贴图工具栏视图（SwiftUI 高对比胶囊浮条）

struct PinnedToolbarView: View {
    @Bindable var state: AnnotationState
    @Bindable var pinnedState: PinnedEditorState
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleAnnotation: () -> Void
    let onToggleTranslate: () -> Void
    let onToggleOCR: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            // 选择 / 移动工具
            Button {
                state.activeKind = nil
            } label: {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state.activeKind == nil ? .white : Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(state.activeKind == nil ? Color(nsColor: .controlAccentColor) : .clear)
                    )
            }
            .buttonStyle(LensoPressButtonStyle(scale: 0.92))
            .help("选择与移动 (V)")

            ForEach([AnnotationKind.rect, .ellipse, .arrow, .brush, .text, .mosaic, .highlight], id: \.self) { kind in
                Button {
                    state.activeKind = state.activeKind == kind ? nil : kind
                } label: {
                    Image(systemName: kind.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(state.activeKind == kind ? Color(nsColor: .controlAccentColor) : Color(red: 0.18, green: 0.18, blue: 0.22))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(state.activeKind == kind ? Color(nsColor: .controlAccentColor).opacity(0.15) : .clear)
                        )
                }
                .buttonStyle(LensoPressButtonStyle(scale: 0.92))
                .help(kind.label)
            }

            Divider().frame(height: 18)

            // 标注属性面板快捷入口（点击打开标注设置卡片）
            Button(action: onToggleAnnotation) {
                Circle()
                    .fill(AnnotationPalette[state.colorIndex])
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 1))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(pinnedState.isSidePanelVisible && pinnedState.panelTab == .annotation ? Color(nsColor: .controlAccentColor).opacity(0.15) : .clear)
                    )
            }
            .buttonStyle(LensoPressButtonStyle(scale: 0.92))
            .help("标注调色盘与粗细设置")

            Divider().frame(height: 18)

            // 撤销 / 重做
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22).opacity(state.canUndo ? 1.0 : 0.35))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(LensoPressButtonStyle(scale: 0.92))
            .disabled(!state.canUndo)
            .help("撤销 (⌘Z)")

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22).opacity(state.canRedo ? 1.0 : 0.35))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(LensoPressButtonStyle(scale: 0.92))
            .disabled(!state.canRedo)
            .help("重做 (⇧⌘Z)")

            Divider().frame(height: 18)

            // 翻译
            Button(action: onToggleTranslate) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pinnedState.isSidePanelVisible && pinnedState.panelTab == .translate ? Color(nsColor: .controlAccentColor) : Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(pinnedState.isSidePanelVisible && pinnedState.panelTab == .translate ? Color(nsColor: .controlAccentColor).opacity(0.15) : .clear)
                    )
            }
            .buttonStyle(LensoPressButtonStyle(scale: 0.92))
            .help("智能翻译卡片")

            // OCR
            Button(action: onToggleOCR) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pinnedState.isSidePanelVisible && pinnedState.panelTab == .ocr ? Color(nsColor: .controlAccentColor) : Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(pinnedState.isSidePanelVisible && pinnedState.panelTab == .ocr ? Color(nsColor: .controlAccentColor).opacity(0.15) : .clear)
                    )
            }
            .buttonStyle(LensoPressButtonStyle(scale: 0.92))
            .help("文字识别 (OCR) 卡片")

            // 复制
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(LensoPressButtonStyle(scale: 0.92))
            .help("复制到剪贴板 (⌘C)")

            // 保存
            Button(action: onSave) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(LensoPressButtonStyle(scale: 0.92))
            .help("保存到历史记录 (⌘S)")

            // 关闭
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(LensoPressButtonStyle(scale: 0.92))
            .help("关闭贴图")
        }
        .lensoAnimation(LensoAnimations.snappy, value: state.activeKind, reduceMotion: reduceMotion)
        .lensoAnimation(LensoAnimations.snappy, value: pinnedState.panelTab, reduceMotion: reduceMotion)
        .lensoAnimation(LensoAnimations.snappy, value: pinnedState.isSidePanelVisible, reduceMotion: reduceMotion)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color(red: 0.985, green: 0.988, blue: 1.0))
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
    }
}
