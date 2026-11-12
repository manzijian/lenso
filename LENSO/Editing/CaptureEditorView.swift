import SwiftUI
import AppKit
import CoreGraphics

/// 完整截图编辑器（参考产品图 2）：
/// 全屏冻结画面 + 选区（8 手柄可调整）+ 底部工具栏 + 右侧属性面板 + 完成保存
struct CaptureEditorView: View {
    let frozenImage: CGImage      // 全屏冻结帧（屏幕坐标 = 图像坐标 × scale）
    let screenFrame: CGRect       // 全局逻辑坐标
    var initialSelection: CGRect  // 全局逻辑坐标
    let onComplete: (CGImage?) -> Void   // 完成时回传最终图像（nil = 取消）
    let onQuickCopy: (CGImage) -> Void
    let onPin: (CGImage, CGRect) -> Void

    @State var state = AnnotationState()
    @State var selection: CGRect
    @State private var drawingAnnotation = false

    /// 是否显示右侧属性面板（可关闭，避免遮挡）
    @State private var isSidePanelVisible = true
    /// 右侧面板页签
    @State private var panelTab: PanelTab = .annotation
    /// OCR 与翻译的运行状态
    @State private var ocrLines: [RecognizedText] = []
    @State private var ocrPhase: OCRPhase = .idle
    @State private var ocrErrorMessage: String?
    @State private var translations: [UUID: String] = [:]
    @State private var translationPhase: TranslationPhase = .idle
    @State private var translationErrorMessage: String?
    @State private var ocrTask: Task<Void, Never>?
    @State private var translationTask: Task<Void, Never>?
    @State private var justSavedNote = false

    /// 冻结图与屏幕的像素比
    var imageScale: CGFloat {
        CGFloat(frozenImage.width) / screenFrame.width
    }

    init(frozenImage: CGImage, screenFrame: CGRect, initialSelection: CGRect,
         onComplete: @escaping (CGImage?) -> Void,
         onQuickCopy: @escaping (CGImage) -> Void,
         onPin: @escaping (CGImage, CGRect) -> Void) {
        self.frozenImage = frozenImage
        self.screenFrame = screenFrame
        self.initialSelection = initialSelection
        self.onComplete = onComplete
        self.onQuickCopy = onQuickCopy
        self.onPin = onPin
        // 编辑器内部统一用「屏幕内坐标、原点左上」——和 CGImage 的行序一致。
        // 传进来的 initialSelection 是 AppKit 全局坐标（原点左下），这里换算一次，
        // 之后所有绘制/裁剪/标注都在这一个坐标系里做。
        _selection = State(initialValue: Self.localTopDown(initialSelection, in: screenFrame))
    }

    /// AppKit 全局坐标 → 屏幕内坐标（原点左上，y 向下）
    static func localTopDown(_ rect: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    var body: some View {
        ZStack {
            // 冻结画面
            Image(decorative: frozenImage, scale: 1)
                .resizable()
                .frame(width: screenFrame.width, height: screenFrame.height)
                .position(x: screenFrame.width / 2, y: screenFrame.height / 2)
                .allowsHitTesting(false)

            // 选区内容视图（挖空 + 手柄 + 标注渲染 + 尺寸调整 + 双击确定复制）
            SelectionContent(
                frozenImage: frozenImage,
                screenFrame: screenFrame,
                selection: selection,
                state: state,
                imageScale: imageScale,
                onSelectionChange: { selection = $0 },
                onConfirm: { finishEditing() }
            )

            // 工具栏：紧贴选区下方（随选区移动），右侧属性面板紧贴选区右侧
            toolbarAndPanel

            // 文字标注输入框（文字工具点按后出现）
            if let point = state.textEditingPoint {
                AnnotationTextField(
                    color: NSColor(AnnotationPalette[state.colorIndex]),
                    onCommit: { commitTextEditing($0) },
                    onCancel: { state.textEditingPoint = nil }
                )
                .frame(width: 260, height: 30)
                .position(x: textFieldCenter(for: point).x, y: textFieldCenter(for: point).y)
            }
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .background(Color.black.opacity(0.001)) // 接管点击
        .onExitCommand { discard() }           // Esc 取消
        .onKeyPress(.return) {
            finishEditing()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            nudgeSelection(dx: -1, dy: 0)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            nudgeSelection(dx: 1, dy: 0)
            return .handled
        }
        .onKeyPress(.upArrow) {
            nudgeSelection(dx: 0, dy: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            nudgeSelection(dx: 0, dy: 1)
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorScrollWheel)) { note in
            guard let event = note.object as? NSEvent else { return }
            handleScrollWheel(event)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorRightClick)) { _ in
            if state.textEditingPoint != nil {
                state.textEditingPoint = nil
            } else if state.activeKind != nil {
                state.activeKind = nil
            } else {
                discard()
            }
        }
    }

    /// 鼠标滚轮缩放选区大小（以鼠标指针所在位置为锚点缩放）
    private func handleScrollWheel(_ event: NSEvent) {
        guard state.textEditingPoint == nil else { return }
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.05 else { return }

        let factor: CGFloat = delta > 0 ? 1.04 : 0.96
        let loc = event.locationInWindow
        // AppKit 窗口坐标原点在左下，转换为屏幕内坐标（原点在左上）
        let mouseInScreen = CGPoint(
            x: loc.x,
            y: screenFrame.height - loc.y
        )

        let newWidth = max(24, min(screenFrame.width, selection.width * factor))
        let newHeight = max(24, min(screenFrame.height, selection.height * factor))

        // 以鼠标为中心缩放（如果鼠标在选区内），否则以选区中心缩放
        let anchorX = selection.contains(mouseInScreen) ? mouseInScreen.x : selection.midX
        let anchorY = selection.contains(mouseInScreen) ? mouseInScreen.y : selection.midY

        let relX = (anchorX - selection.minX) / max(1, selection.width)
        let relY = (anchorY - selection.minY) / max(1, selection.height)

        let newX = min(max(0, anchorX - newWidth * relX), screenFrame.width - newWidth)
        let newY = min(max(0, anchorY - newHeight * relY), screenFrame.height - newHeight)

        selection = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    /// 方向键微调选区
    private func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard state.textEditingPoint == nil else { return }
        let moved = selection.offsetBy(dx: dx, dy: dy)
        let clamped = CGRect(
            x: min(max(0, moved.minX), screenFrame.width - moved.width),
            y: min(max(0, moved.minY), screenFrame.height - moved.height),
            width: moved.width,
            height: moved.height
        )
        selection = clamped
    }

    /// 丢弃本次截图
    private func discard() {
        ocrTask?.cancel()
        translationTask?.cancel()
        onComplete(nil)
    }

    /// 提交文字标注：空文本不建标注；工具保持激活，可连续加下一条
    private func commitTextEditing(_ text: String) {
        guard let point = state.textEditingPoint else { return }
        state.textEditingPoint = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let size = NSAttributedString(string: trimmed, attributes: [.font: font]).size()
        let end = CGPoint(
            x: min(1, point.x + size.width / max(1, selection.width)),
            y: min(1, point.y + size.height / max(1, selection.height))
        )
        state.push(Annotation(
            kind: .text, start: point, end: end,
            colorIndex: state.colorIndex, strokeWidth: state.strokeWidth, text: trimmed
        ))
    }

    /// 输入框中心点：落点 + 半个框宽/高，夹在屏幕内
    private func textFieldCenter(for point: CGPoint) -> CGPoint {
        let topLeft = CGPoint(
            x: selection.minX + point.x * selection.width,
            y: selection.minY + point.y * selection.height
        )
        return CGPoint(
            x: min(max(topLeft.x + 130, 130), screenFrame.width - 130),
            y: min(max(topLeft.y + 15, 15), screenFrame.height - 15)
        )
    }

    /// 钉图：合成后交给 Coordinator 浮在屏幕上
    private func pinImage() {
        guard let composited = renderFinalImage() else { return }
        // 转换当前选区为 AppKit 全局坐标，使贴图浮窗直接定格在当前选区位置
        let globalRect = CGRect(
            x: screenFrame.minX + selection.minX,
            y: screenFrame.maxY - selection.maxY,
            width: selection.width,
            height: selection.height
        )
        onPin(composited, globalRect)
    }

    /// 工具栏与属性面板挂载
    @ViewBuilder
    private var toolbarAndPanel: some View {
        let localSel = selection
        let toolbarSize = CGSize(width: 610, height: 52)
        let panelSize = CGSize(width: 270, height: 410)
        let layout = CaptureEditorLayout.calculateLayout(
            selection: localSel,
            screenSize: screenFrame.size,
            toolbarSize: toolbarSize,
            panelSize: panelSize
        )

        Group {
            if isSidePanelVisible {
                sidePanel
                    .frame(width: panelSize.width)
                    .position(x: layout.panelFrame.midX, y: layout.panelFrame.midY)
                    .zIndex(1)
            }

            bottomToolbar
                .frame(width: toolbarSize.width)
                .position(x: layout.toolbarFrame.midX, y: layout.toolbarFrame.midY)
                .zIndex(10)
        }
    }

    // MARK: - 底部工具栏

    private var bottomToolbar: some View {
        CaptureEditorToolbarView(
            state: state,
            isSidePanelVisible: $isSidePanelVisible,
            panelTab: $panelTab,
            ocrPhase: ocrPhase,
            onRunOCR: { runOCR() },
            onPin: { pinImage() },
            onFinish: { finishEditing() },
            onDiscard: { discard() }
        )
    }

    // MARK: - 右侧属性面板（严格对齐参考图 3）

    private var sidePanel: some View {
        CaptureEditorSidePanelView(
            state: state,
            isSidePanelVisible: $isSidePanelVisible,
            panelTab: $panelTab,
            ocrPhase: ocrPhase,
            ocrLines: ocrLines,
            ocrErrorMessage: ocrErrorMessage,
            translationPhase: translationPhase,
            translations: translations,
            translationErrorMessage: translationErrorMessage,
            justSavedNote: justSavedNote,
            onRunOCR: { runOCR() },
            onRunTranslation: { runTranslation() },
            onCopyText: { copyText($0) },
            onSaveOCRToNotes: { saveOCRToNotes() },
            onQuickCopy: { quickCopy() }
        )
    }


    // MARK: - Actions

    private func finishEditing() {
        ocrTask?.cancel()
        translationTask?.cancel()
        let composited = renderFinalImage()
        onComplete(composited)
    }

    private func quickCopy() {
        let composited = renderFinalImage()
        guard let composited else { return }
        onQuickCopy(composited)
    }

    // MARK: - OCR 与翻译（本地实现，第三方走 ProviderRegistry 预留口子）

    /// 当前选区的原图裁剪（不带标注，OCR 用）
    private func selectionCropImage() -> CGImage? {
        // selection 是屏幕内坐标（原点左上），CGImage.cropping 用的也是左上原点 → 直接乘比例
        let pxRect = CGRect(
            x: selection.origin.x * imageScale,
            y: selection.origin.y * imageScale,
            width: selection.width * imageScale,
            height: selection.height * imageScale
        ).integral
        return frozenImage.cropping(to: pxRect)
    }

    /// 跑 OCR；thenTranslate 为真时识别完自动接翻译
    private func runOCR(thenTranslate: Bool = false) {
        panelTab = .ocr
        ocrTask?.cancel()
        ocrPhase = .running
        ocrErrorMessage = nil
        ocrLines = []
        translations = [:]
        translationPhase = .idle
        justSavedNote = false
        guard let image = selectionCropImage() else {
            ocrPhase = .failed
            ocrErrorMessage = "选区图片获取失败"
            return
        }
        ocrTask = Task {
            do {
                let lines = try await ProviderRegistry.ocr.recognizeText(in: image, languages: ["zh-Hans", "en-US"])
                guard !Task.isCancelled else { return }
                ocrLines = lines
                ocrPhase = lines.isEmpty ? .empty : .done
                if thenTranslate, !lines.isEmpty {
                    panelTab = .translate
                    translateLines()
                }
            } catch {
                guard !Task.isCancelled else { return }
                ocrPhase = .failed
                ocrErrorMessage = error.localizedDescription
            }
        }
    }

    /// 点翻译：有识别结果直接翻，没有先跑 OCR 再翻
    private func runTranslation() {
        panelTab = .translate
        if ocrLines.isEmpty {
            runOCR(thenTranslate: true)
            return
        }
        translateLines()
    }

    /// 逐行翻译（保持原文/译文一一对应；单行失败不阻断其他行）
    private func translateLines() {
        translationTask?.cancel()
        translationPhase = .running
        translationErrorMessage = nil
        let lines = ocrLines
        translationTask = Task {
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
            translations = results
            if let firstError, results.values.allSatisfy({ $0.isEmpty }) {
                translationPhase = .failed
                translationErrorMessage = firstError
            } else {
                translationPhase = .done
                translationErrorMessage = nil
            }
        }
    }

    /// 复制文字（写完剪贴板要告诉监听器这是自己写的，别当成新剪贴记录）
    private func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ClipboardMonitor.shared.markSelfWrite()
    }

    /// 把识别结果存进文字收纳
    private func saveOCRToNotes() {
        let content = ocrLines.map(\.text).joined(separator: "\n")
        guard !content.isEmpty else { return }
        do {
            _ = try ScreenshotStore.shared.createTextNote(content: content, sourceApp: "lenso 截图识别")
            justSavedNote = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                justSavedNote = false
            }
        } catch {
            ocrErrorMessage = "存入失败：\(error.localizedDescription)"
        }
    }


}




