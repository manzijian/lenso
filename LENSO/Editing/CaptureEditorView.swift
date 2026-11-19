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
    /// 正在输入的文字（提到父层持有：点画面确认时也能拿到内容）
    @State private var editingText = ""

    /// 是否显示右侧面板（默认收起，只在需要看 OCR / 翻译结果时打开，避免遮挡画面）
    @State private var isSidePanelVisible = false
    /// 右侧面板页签
    @State private var panelTab: PanelTab = .ocr
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
    @State private var keyMonitor: Any?
    /// 马赛克预览用的块状图（整屏冻结帧的低分辨率重采样，只算一次）
    private let mosaicPreview: CGImage?

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
        let scale = CGFloat(frozenImage.width) / max(1, screenFrame.width)
        self.mosaicPreview = Self.makePixelatedPreview(
            frozenImage, blockPx: max(6, Int(14 * scale))
        )
    }

    /// 生成马赛克预览图：先缩到 1/block，再用最近邻放回半尺寸。
    /// 半尺寸是为了省内存，绘制时块仍然是清晰的方块。
    static func makePixelatedPreview(_ image: CGImage, blockPx: Int) -> CGImage? {
        let w = image.width, h = image.height
        let smallW = max(1, w / blockPx), smallH = max(1, h / blockPx)
        guard let smallCtx = CGContext(
            data: nil, width: smallW, height: smallH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        smallCtx.interpolationQuality = .medium
        smallCtx.draw(image, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let small = smallCtx.makeImage() else { return nil }

        let outW = max(1, w / 2), outH = max(1, h / 2)
        guard let outCtx = CGContext(
            data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        outCtx.interpolationQuality = .none
        outCtx.draw(small, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return outCtx.makeImage()
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
        ZStack(alignment: .topLeading) {
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
                mosaicPreview: mosaicPreview,
                imageScale: imageScale,
                onSelectionChange: { updateSelection($0) },
                onConfirm: { finishEditing() }
            )
            .frame(width: screenFrame.width, height: screenFrame.height)

            // 文字输入中：点画面上任意位置即确认（不用再按回车）
            if state.textEditingPoint != nil {
                Color.black.opacity(0.001)
                    .frame(width: screenFrame.width, height: screenFrame.height)
                    .contentShape(Rectangle())
                    .onTapGesture { commitCurrentText() }
                    .zIndex(15)
            }

            // 工具栏：紧贴选区下方（随选区移动），右侧属性面板紧贴选区右侧
            toolbarAndPanel

            // 文字标注输入框：与 Snipaste 一样直接落在点击位置，
            // 透明底 + 细边框，边打字边在原位看到文字（不是弹一个白色输入条）
            if let point = state.textEditingPoint {
                let origin = textFieldOrigin(for: point)
                AnnotationTextField(
                    text: $editingText,
                    color: AnnotationPalette[state.colorIndex],
                    onCommit: { commitTextEditing($0) },
                    onCancel: { state.textEditingPoint = nil }
                )
                .offset(x: origin.x, y: origin.y)
                .zIndex(20)
            }
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .background(Color.black.opacity(0.001)) // 接管点击
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: .editorRightClick)) { _ in
            if state.textEditingPoint != nil {
                state.textEditingPoint = nil
            } else if state.activeKind != nil {
                state.activeKind = nil
            } else {
                discard()
            }
        }
        .onChange(of: state.textEditingPoint) { oldValue, point in
            // 开始写字时清空上一条内容，并确保编辑器是 key window，
            // 否则 SwiftUI TextField 拿不到输入焦点
            guard point != nil else { return }
            if oldValue == nil { editingText = "" }
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window is EditorPanel && window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// 键盘统一由本地事件监听处理：
    /// - 文字输入框是第一响应者（field editor 为 NSTextView）时，所有按键原样放行，
    ///   这样中文输入法的候选、回车确认、方向键选词都不会被截走；
    /// - 其余情况才接管 ⏎ / 方向键 / Esc。
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = event.window, window.level == .screenSaver else { return event }
            // 正在输入文字时所有按键原样放行（回车交给 TextField 提交，Esc 交给 onExitCommand）
            if state.textEditingPoint != nil || Self.isTextInputActive(in: window) { return event }

            switch event.keyCode {
            case 53: // Esc
                if state.textEditingPoint != nil {
                    state.textEditingPoint = nil
                } else {
                    discard()
                }
                return nil
            case 36, 76: // Return / Enter
                guard state.textEditingPoint == nil else { return event }
                finishEditing()
                return nil
            case 123: nudgeSelection(dx: -1, dy: 0); return nil
            case 124: nudgeSelection(dx: 1, dy: 0); return nil
            case 125: nudgeSelection(dx: 0, dy: 1); return nil
            case 126: nudgeSelection(dx: 0, dy: -1); return nil
            default:
                return event
            }
        }
    }

    /// 当前窗口是否处于文字输入状态（field editor / NSTextField 的输入视图）
    private static func isTextInputActive(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if responder is NSTextView { return true }
        if let text = responder as? NSText, text.isEditable { return true }
        return false
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// 选区移动/缩放：先按绝对位置重算标注，保证标注钉在画面内容上、不被拉变形
    private func updateSelection(_ newSelection: CGRect) {
        guard newSelection != selection else { return }
        state.remapAnnotations(from: selection, to: newSelection)
        selection = newSelection
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
        updateSelection(clamped)
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
        editingText = ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let size = NSAttributedString(string: trimmed, attributes: [.font: font]).size()
        let end = CGPoint(
            x: min(1, point.x + size.width / max(1, selection.width)),
            y: min(1, point.y + size.height / max(1, selection.height))
        )
        let annotation = Annotation(
            kind: .text, start: point, end: end,
            colorIndex: state.colorIndex, strokeWidth: state.strokeWidth, text: trimmed
        )
        state.push(annotation)
        // 刚写好的文字直接选中并切回选择工具，可以立刻拖动位置
        state.activeKind = nil
        state.selectedAnnotationID = annotation.id
    }

    /// 点击画面空白处结束输入（Snipaste 习惯：不用按回车）
    private func commitCurrentText() {
        guard state.textEditingPoint != nil else { return }
        commitTextEditing(editingText)
    }

    /// 输入框左上角：直接落在点击点上（Snipaste 原位输入），夹在屏幕内
    private func textFieldOrigin(for point: CGPoint) -> CGPoint {
        let topLeft = CGPoint(
            x: selection.minX + point.x * selection.width,
            y: selection.minY + point.y * selection.height
        )
        return CGPoint(
            x: min(max(0, topLeft.x), max(0, screenFrame.width - 140)),
            y: min(max(0, topLeft.y), max(0, screenFrame.height - 26))
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
        let showOptions = state.activeKind != nil
        let toolbarSize = CGSize(width: 610, height: showOptions ? 94 : 52)
        let panelSize = CGSize(width: 300, height: 430)
        let layout = CaptureEditorLayout.calculateLayout(
            selection: localSel,
            screenSize: screenFrame.size,
            toolbarSize: toolbarSize,
            panelSize: panelSize
        )

        Group {
            // 右侧面板只承载 OCR / 翻译结果，标注属性已经收进工具栏上方的属性条
            if isSidePanelVisible && panelTab != .annotation {
                LayerHostedPanel(
                    content: AnyView(sidePanel),
                    panelSize: panelSize,
                    origin: layout.panelFrame.origin
                )
                .frame(width: screenFrame.width, height: screenFrame.height)
                .position(x: screenFrame.width / 2, y: screenFrame.height / 2)
                .zIndex(1)
            }

            VStack(spacing: 8) {
                if showOptions {
                    CaptureEditorOptionsBar(state: state)
                }
                bottomToolbar
            }
            .frame(width: toolbarSize.width, height: toolbarSize.height)
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
            onSaveOCRToNotes: { saveOCRToNotes() }
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




