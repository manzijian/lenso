import SwiftUI
import AppKit
import CoreGraphics

/// 右侧面板页签：标注 / OCR / 翻译
enum PanelTab { case annotation, ocr, translate }

/// OCR 运行阶段
enum OCRPhase { case idle, running, done, empty, failed }

/// 翻译运行阶段
enum TranslationPhase { case idle, running, done, failed }

/// 完整截图编辑器（参考产品图 2）：
/// 全屏冻结画面 + 选区（8 手柄可调整）+ 底部工具栏 + 右侧属性面板 + 完成保存
struct CaptureEditorView: View {
    let frozenImage: CGImage      // 全屏冻结帧（屏幕坐标 = 图像坐标 × scale）
    let screenFrame: CGRect       // 全局逻辑坐标
    var initialSelection: CGRect  // 全局逻辑坐标
    let onComplete: (CGImage?) -> Void   // 完成时回传最终图像（nil = 取消）
    let onQuickCopy: (CGImage) -> Void
    let onPin: (CGImage, CGRect) -> Void

    @State private var state = AnnotationState()
    @State private var selection: CGRect
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
    @State private var ocrDisplayMode = 0
    @State private var translationDisplayMode = 0

    /// 冻结图与屏幕的像素比
    private var imageScale: CGFloat {
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

    // MARK: - 布局计算与避免遮挡

    private struct EditorLayoutPositions {
        let toolbarFrame: CGRect
        let panelFrame: CGRect
    }

    /// 计算工具栏与属性面板（OCR卡片）位置，严格保证二者永不重叠，避免保存/取消按钮被遮挡
    private static func calculateLayout(
        selection: CGRect,
        screenSize: CGSize,
        toolbarSize: CGSize,
        panelSize: CGSize
    ) -> EditorLayoutPositions {
        let margin: CGFloat = 8
        let spacing: CGFloat = 12

        // 1. 计算 bottomToolbar 位置
        let toolbarX = min(
            max(toolbarSize.width / 2 + margin, selection.midX),
            screenSize.width - toolbarSize.width / 2 - margin
        )

        // 优先在选区下方；放不下放选区上方；都放不下放选区内底端（Snipaste 策略）
        let toolbarY: CGFloat
        if selection.maxY + spacing + toolbarSize.height + margin <= screenSize.height {
            toolbarY = selection.maxY + spacing + toolbarSize.height / 2
        } else if selection.minY - spacing - toolbarSize.height >= margin {
            toolbarY = selection.minY - spacing - toolbarSize.height / 2
        } else {
            toolbarY = min(
                selection.maxY - spacing - toolbarSize.height / 2,
                screenSize.height - toolbarSize.height / 2 - margin
            )
        }

        let toolbarRect = CGRect(
            x: toolbarX - toolbarSize.width / 2,
            y: toolbarY - toolbarSize.height / 2,
            width: toolbarSize.width,
            height: toolbarSize.height
        )

        // 2. 计算 sidePanel（OCR/属性面板）位置
        // 优先放选区右侧；右侧不够放选区左侧；两边都不够放屏幕右侧
        let panelX: CGFloat
        if selection.maxX + spacing + panelSize.width + margin <= screenSize.width {
            panelX = selection.maxX + spacing + panelSize.width / 2
        } else if selection.minX - spacing - panelSize.width >= margin {
            panelX = selection.minX - spacing - panelSize.width / 2
        } else {
            panelX = screenSize.width - panelSize.width / 2 - margin
        }

        let panelLeft = panelX - panelSize.width / 2
        let panelRight = panelX + panelSize.width / 2

        // 判断 X 轴是否与底部工具栏重叠（留出间距）
        let overlapsX = panelLeft < toolbarRect.maxX + spacing && panelRight > toolbarRect.minX - spacing

        var panelY: CGFloat
        if overlapsX {
            // X 轴重叠：垂直方向严格避让工具栏，绝不能遮挡保存/取消按钮
            if toolbarRect.midY > screenSize.height / 2 {
                // 工具栏偏屏幕下方：属性面板放置在工具栏上方
                let maxPanelBottom = toolbarRect.minY - spacing
                panelY = maxPanelBottom - panelSize.height / 2
                panelY = max(panelSize.height / 2 + margin, panelY)
            } else {
                // 工具栏偏屏幕上方：属性面板放置在工具栏下方
                let minPanelTop = toolbarRect.maxY + spacing
                panelY = minPanelTop + panelSize.height / 2
                panelY = min(screenSize.height - panelSize.height / 2 - margin, panelY)
            }
        } else {
            // X 轴不重叠：垂直居中于选区
            panelY = min(
                max(panelSize.height / 2 + margin, selection.midY),
                screenSize.height - panelSize.height / 2 - margin
            )
        }

        let panelRect = CGRect(
            x: panelX - panelSize.width / 2,
            y: panelY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )

        return EditorLayoutPositions(toolbarFrame: toolbarRect, panelFrame: panelRect)
    }

    /// 工具栏与属性面板挂载
    @ViewBuilder
    private var toolbarAndPanel: some View {
        let localSel = selection
        let toolbarSize = CGSize(width: 610, height: 52)
        let panelSize = CGSize(width: 270, height: 410)
        let layout = Self.calculateLayout(
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
        HStack(spacing: 4) {
            // 选择工具（默认激活，蓝色圆底）
            ZStack {
                Circle()
                    .fill(state.activeKind == nil ? Color(nsColor: .controlAccentColor) : .clear)
                    .frame(width: 30, height: 30)
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state.activeKind == nil ? .white : Color(red: 0.18, green: 0.18, blue: 0.22))
            }
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
            .onTapGesture { state.activeKind = nil }

            ForEach([AnnotationKind.rect, .ellipse, .arrow, .brush, .text, .mosaic, .highlight], id: \.self) { kind in
                ToolIcon(icon: kind.icon, kind: kind, state: state) {
                    state.activeKind = state.activeKind == kind ? nil : kind
                    if kind == .mosaic { state.mosaicEnabled = true }
                    if kind == .highlight { state.highlightEnabled = true }
                }
            }

            Divider().frame(height: 22)

            ToolIcon(icon: "arrow.uturn.backward", kind: nil, state: state, disabled: !state.canUndo) { state.undo() }
            ToolIcon(icon: "arrow.uturn.forward", kind: nil, state: state, disabled: !state.canRedo) { state.redo() }

            // OCR 快捷入口：点按直接打开 OCR 卡片
            ToolIcon(icon: "doc.text.viewfinder", kind: nil, state: state) {
                if isSidePanelVisible && panelTab == .ocr {
                    isSidePanelVisible = false
                } else {
                    isSidePanelVisible = true
                    panelTab = .ocr
                    if ocrPhase == .idle { runOCR() }
                }
            }
            .help("文字识别（OCR）")

            // 钉图：把当前合成结果钉在屏幕最上层
            Image(systemName: "pin.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .onTapGesture { pinImage() }
                .help("钉在屏幕上")

            Text("完成")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(nsColor: .controlAccentColor)))
                .onTapGesture { finishEditing() }

            // 丢弃本次截图（不保存）
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.06)))
                .contentShape(Rectangle())
                .onTapGesture { discard() }
                .help("取消截图（Esc）")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            // 实体高亮白底（不透底），无论在多么黑的终端或壁纸上都始终清晰高亮
            Capsule()
                .fill(Color(red: 0.985, green: 0.988, blue: 1.0))
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 5)
    }

    // MARK: - 右侧属性面板（严格对齐参考图 3）

    private var sidePanel: some View {
        VStack(spacing: 14) {
            // 顶部工具行：标注 / 翻译 / OCR / 关闭
            HStack(spacing: 16) {
                SideTool(icon: "highlighter", label: "标注", active: panelTab == .annotation) {
                    panelTab = .annotation
                    state.activeKind = .brush
                }
                SideTool(icon: "character.bubble", label: "翻译", active: panelTab == .translate) {
                    runTranslation()
                }
                SideTool(icon: "doc.text.viewfinder", label: "OCR", active: panelTab == .ocr) {
                    if ocrPhase == .idle { runOCR() } else { panelTab = .ocr }
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
                quickCopy()
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
                                OCRLineRow(line: line) { copyText(line.text) }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            HStack(spacing: 8) {
                MiniButton(label: "重新识别") { runOCR() }
                MiniButton(label: "全部复制", disabled: ocrLines.isEmpty) {
                    copyText(ocrLines.map(\.text).joined(separator: "\n"))
                }
                MiniButton(label: justSavedNote ? "已存入" : "存入收纳", disabled: ocrLines.isEmpty) {
                    saveOCRToNotes()
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
                Text("把识别到的文字翻成目标语言（本地模型，不联网）。")
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
                                    copyText(translated.isEmpty ? line.text : translated)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            HStack(spacing: 8) {
                MiniButton(label: "重新翻译") { runTranslation() }
                MiniButton(label: "全部复制译文", disabled: translations.isEmpty) {
                    let text = ocrLines.map { translations[$0.id] ?? "" }.joined(separator: "\n")
                    copyText(text)
                }
            }
        }
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

    /// 合成：冻结帧裁剪选区 + 标注
    private func renderFinalImage() -> CGImage? {
        let pxRect = CGRect(
            x: selection.origin.x * imageScale,
            y: selection.origin.y * imageScale,
            width: selection.width * imageScale,
            height: selection.height * imageScale
        ).integral
        let base = frozenImage.cropping(to: pxRect)
        guard var base, !state.annotations.isEmpty else { return base }

        // 画标注
        let w = Int(pxRect.width), h = Int(pxRect.height)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setLineCap(.round)

        let sw = CGFloat(w), sh = CGFloat(h)
        for annotation in state.annotations {
            let color = NSColor(AnnotationPalette[annotation.colorIndex]).withAlphaComponent(annotation.kind == .highlight ? 0.4 : 1)
            ctx.setStrokeColor(color.cgColor)
            ctx.setFillColor(color.cgColor)
            ctx.setLineWidth(annotation.strokeWidth * imageScale)

            let p1 = CGPoint(x: annotation.start.x * sw, y: (1 - annotation.start.y) * sh)
            let p2 = CGPoint(x: annotation.end.x * sw, y: (1 - annotation.end.y) * sh)
            let rect = CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
                              width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))

            switch annotation.kind {
            case .rect:
                ctx.stroke(rect)
            case .ellipse:
                ctx.strokeEllipse(in: rect)
            case .arrow:
                drawArrow(ctx, from: p1, to: p2, headLen: 12 * imageScale)
            case .brush:
                ctx.move(to: p1)
                ctx.addLine(to: p2)
                ctx.strokePath()
            case .highlight:
                ctx.setFillColor(color.cgColor)
                ctx.fill(rect)
            case .mosaic:
                applyMosaic(ctx, image: base, rect: CGRect(
                    x: min(p1.x, p2.x), y: min(p1.y, p2.y),
                    width: rect.width, height: rect.height
                ))
            case .text:
                // 文字标注：按所选颜色把真文字画进导出图（翻转坐标系里按左上锚点排版）
                let fontSize = 16 * imageScale
                let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(AnnotationPalette[annotation.colorIndex])
                ]
                let attr = NSAttributedString(string: annotation.text, attributes: attrs)
                let topDownRect = CGRect(
                    x: annotation.start.x * sw,
                    y: annotation.start.y * sh,
                    width: max(1, (annotation.end.x - annotation.start.x) * sw),
                    height: max(fontSize * 1.2, (annotation.end.y - annotation.start.y) * sh)
                )
                let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = nsCtx
                attr.draw(in: topDownRect)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        base = ctx.makeImage() ?? base
        return base
    }

    private func drawArrow(_ ctx: CGContext, from: CGPoint, to: CGPoint, headLen: CGFloat) {
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
        let angle = atan2(to.y - from.y, to.x - from.x)
        for delta in [2.5, -2.5] {
            let hx = to.x - headLen * cos(angle + delta)
            let hy = to.y - headLen * sin(angle + delta)
            ctx.move(to: to)
            ctx.addLine(to: CGPoint(x: hx, y: hy))
            ctx.strokePath()
        }
    }

    /// 马赛克：选区内 16px 块取平均色
    private func applyMosaic(_ ctx: CGContext, image: CGImage, rect: CGRect) {
        let blockSize = max(8, 16 * Int(imageScale) / 2)
        guard let data = ctx.makeImage() else { return }
        // 简化：用低分辨率重采样回贴
        let smallW = max(1, Int(rect.width) / blockSize)
        let smallH = max(1, Int(rect.height) / blockSize)
        guard let smallCtx = CGContext(
            data: nil, width: smallW, height: smallH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        smallCtx.interpolationQuality = .low
        smallCtx.draw(image, in: CGRect(x: -rect.origin.x / CGFloat(blockSize), y: -rect.origin.y / CGFloat(blockSize),
                                        width: CGFloat(smallW) + rect.width / CGFloat(blockSize),
                                        height: CGFloat(smallH) + rect.height / CGFloat(blockSize)))
        guard let small = smallCtx.makeImage() else { return }
        ctx.saveGState()
        ctx.clip(to: [rect])
        ctx.interpolationQuality = .none
        ctx.draw(small, in: rect)
        ctx.restoreGState()
    }
}

// MARK: - 选区内容（挖空 + 8 个调整手柄 + 实时尺寸徽标 + 标注画布）

enum SelectionHandle: CaseIterable {
    case topLeft, topEdge, topRight, rightEdge, bottomRight, bottomEdge, bottomLeft, leftEdge

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: true
        default: false
        }
    }
}

private struct SelectionContent: View {
    let frozenImage: CGImage
    let screenFrame: CGRect
    let selection: CGRect
    let state: AnnotationState
    let imageScale: CGFloat
    let onSelectionChange: (CGRect) -> Void
    let onConfirm: () -> Void

    @State private var dragOrigin: CGPoint? = nil
    @State private var selectionOrigin: CGRect? = nil
    @State private var handleDragOrigin: CGPoint? = nil

    var body: some View {
        ZStack {
            // 暗幕层（全屏，选区挖空）：底层完整冻结图透出来，零延迟零卡顿
            Canvas { context, size in
                let localSel = selection
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.3)))
                context.blendMode = .clear
                context.fill(Path(localSel), with: .color(.white))
                context.blendMode = .normal
                context.stroke(Path(localSel), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            }
            .frame(width: screenFrame.width, height: screenFrame.height)
            .position(x: screenFrame.midX - screenFrame.origin.x, y: screenFrame.midY - screenFrame.origin.y)
            .allowsHitTesting(false)

            // 选区内部：选择工具下允许拖拽移动整个选区；标注工具下绘制标注
            if state.activeKind != nil {
                SelectionInner(
                    selection: selection,
                    state: state
                )
                .frame(width: max(1, selection.width), height: max(1, selection.height))
                .position(x: selection.midX, y: selection.midY)
                .contentShape(Rectangle())
                .gesture(annotationGesture)
            } else {
                SelectionInner(
                    selection: selection,
                    state: state
                )
                .frame(width: max(1, selection.width), height: max(1, selection.height))
                .position(x: selection.midX, y: selection.midY)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        onConfirm()
                    }
                )
            }

            // 尺寸提示（Snipaste 风格胶囊徽标：实时显示宽度与高度）
            sizeBadge

            // 8 个调整手柄（置于最顶层，直接抓取拖动即可调整选区大小）
            handles
        }
    }

    // MARK: - 尺寸指示器

    private var sizeBadge: some View {
        Text("\(Int(selection.width)) × \(Int(selection.height))")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .position(
                x: min(max(45, selection.minX + 45), screenFrame.width - 45),
                y: selection.minY >= 26 ? selection.minY - 14 : selection.minY + 16
            )
            .allowsHitTesting(false)
    }

    // MARK: - 八个手柄与光标

    private var handles: some View {
        ForEach(handlePositions(for: selection), id: \.0) { handle, point in
            let size = handleSize(for: handle)
            ZStack {
                // 增大点击与拖拽热区（26x26），让手柄极其容易被抓取
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: max(26, size.width + 12), height: max(26, size.height + 12))

                // Snipaste 经典白色圆角方块手柄
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color(nsColor: .controlAccentColor), lineWidth: 1.5)
                    )
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
            }
            .position(point)
            .gesture(handleDragGesture(for: handle))
            .onHover { isHovered in
                if isHovered {
                    cursorFor(handle: handle).push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }

    private func handlePositions(for sel: CGRect) -> [(SelectionHandle, CGPoint)] {
        [
            (.topLeft, CGPoint(x: sel.minX, y: sel.minY)),
            (.topEdge, CGPoint(x: sel.midX, y: sel.minY)),
            (.topRight, CGPoint(x: sel.maxX, y: sel.minY)),
            (.rightEdge, CGPoint(x: sel.maxX, y: sel.midY)),
            (.bottomRight, CGPoint(x: sel.maxX, y: sel.maxY)),
            (.bottomEdge, CGPoint(x: sel.midX, y: sel.maxY)),
            (.bottomLeft, CGPoint(x: sel.minX, y: sel.maxY)),
            (.leftEdge, CGPoint(x: sel.minX, y: sel.midY)),
        ]
    }

    private func handleSize(for handle: SelectionHandle) -> CGSize {
        switch handle {
        case .topEdge, .bottomEdge: CGSize(width: 18, height: 7)
        case .leftEdge, .rightEdge: CGSize(width: 7, height: 18)
        default: CGSize(width: 9, height: 9)
        }
    }

    private func cursorFor(handle: SelectionHandle) -> NSCursor {
        switch handle {
        case .leftEdge, .rightEdge:
            return .resizeLeftRight
        case .topEdge, .bottomEdge:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return NSCursor.frameResize(position: .topLeft, directions: .all)
        case .topRight, .bottomLeft:
            return NSCursor.frameResize(position: .topRight, directions: .all)
        }
    }

    // MARK: - 手势

    /// 拖拽手柄调整大小
    private func handleDragGesture(for handle: SelectionHandle) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard state.textEditingPoint == nil else { return }
                if handleDragOrigin == nil {
                    handleDragOrigin = value.startLocation
                    selectionOrigin = selection
                }
                guard let origin = handleDragOrigin, let selOrigin = selectionOrigin else { return }
                let delta = CGPoint(x: value.location.x - origin.x, y: value.location.y - origin.y)
                let newSel = adjustedSelection(handle: handle, origin: selOrigin, delta: delta)
                onSelectionChange(newSel)
            }
            .onEnded { _ in
                handleDragOrigin = nil
                selectionOrigin = nil
            }
    }

    /// 拖拽选区整体平移
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard state.textEditingPoint == nil else { return }
                if dragOrigin == nil {
                    dragOrigin = value.startLocation
                    selectionOrigin = selection
                }
                guard let origin = dragOrigin, let selOrigin = selectionOrigin else { return }
                let delta = CGPoint(x: value.location.x - origin.x, y: value.location.y - origin.y)
                let newSel = adjustedSelection(handle: nil, origin: selOrigin, delta: delta)
                onSelectionChange(newSel)
            }
            .onEnded { _ in
                dragOrigin = nil
                selectionOrigin = nil
            }
    }

    private func adjustedSelection(handle: SelectionHandle?, origin: CGRect, delta: CGPoint) -> CGRect {
        guard let handle else {
            let moved = origin.offsetBy(dx: delta.x, dy: delta.y)
            return CGRect(
                x: min(max(0, moved.minX), screenFrame.width - moved.width),
                y: min(max(0, moved.minY), screenFrame.height - moved.height),
                width: moved.width,
                height: moved.height
            )
        }
        var s = origin
        switch handle {
        case .topLeft:
            s = CGRect(
                x: min(origin.maxX - 16, origin.minX + delta.x),
                y: min(origin.maxY - 16, origin.minY + delta.y),
                width: max(16, origin.width - delta.x),
                height: max(16, origin.height - delta.y)
            )
        case .topRight:
            s = CGRect(
                x: origin.minX,
                y: min(origin.maxY - 16, origin.minY + delta.y),
                width: max(16, origin.width + delta.x),
                height: max(16, origin.height - delta.y)
            )
        case .bottomLeft:
            s = CGRect(
                x: min(origin.maxX - 16, origin.minX + delta.x),
                y: origin.minY,
                width: max(16, origin.width - delta.x),
                height: max(16, origin.height + delta.y)
            )
        case .bottomRight:
            s = CGRect(
                x: origin.minX,
                y: origin.minY,
                width: max(16, origin.width + delta.x),
                height: max(16, origin.height + delta.y)
            )
        case .topEdge:
            s = CGRect(
                x: origin.minX,
                y: min(origin.maxY - 16, origin.minY + delta.y),
                width: origin.width,
                height: max(16, origin.height - delta.y)
            )
        case .bottomEdge:
            s = CGRect(
                x: origin.minX,
                y: origin.minY,
                width: origin.width,
                height: max(16, origin.height + delta.y)
            )
        case .leftEdge:
            s = CGRect(
                x: min(origin.maxX - 16, origin.minX + delta.x),
                y: origin.minY,
                width: max(16, origin.width - delta.x),
                height: origin.height
            )
        case .rightEdge:
            s = CGRect(
                x: origin.minX,
                y: origin.minY,
                width: max(16, origin.width + delta.x),
                height: origin.height
            )
        }
        let clamped = s.intersection(CGRect(origin: .zero, size: screenFrame.size))
        return clamped.width >= 16 && clamped.height >= 16 ? clamped : s.standardized
    }

    private var annotationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard let kind = state.activeKind, state.textEditingPoint == nil else { return }
                if kind == .text {
                    guard selection.contains(value.startLocation) else { return }
                    let norm = normalizedPoint(value.startLocation, current: value.location)
                    state.textEditingPoint = norm.start
                    return
                }
                let localStart = value.startLocation
                let norm = normalizedPoint(localStart, current: value.location)
                if state.draft == nil {
                    state.draft = Annotation(
                        kind: kind, start: norm.start, end: norm.end,
                        colorIndex: state.colorIndex, strokeWidth: state.strokeWidth
                    )
                } else {
                    state.draft?.end = norm.end
                }
            }
            .onEnded { _ in
                if let draft = state.draft {
                    state.push(draft)
                    state.draft = nil
                }
            }
    }

    private func normalizedPoint(_ startLocal: CGPoint, current: CGPoint) -> (start: CGPoint, end: CGPoint) {
        let innerStart = CGPoint(
            x: startLocal.x - selection.origin.x,
            y: startLocal.y - selection.origin.y
        )
        let innerCurrent = CGPoint(
            x: current.x - selection.origin.x,
            y: current.y - selection.origin.y
        )
        func norm(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(1, max(0, p.x / max(1, selection.width))),
                    y: min(1, max(0, p.y / max(1, selection.height))))
        }
        return (norm(innerStart), norm(innerCurrent))
    }
}

// MARK: - 选区内部（标注渲染）

private struct SelectionInner: View {
    let selection: CGRect
    let state: AnnotationState

    var body: some View {
        Canvas { context, size in
            let sw = size.width, sh = size.height
            var all = state.annotations
            if let draft = state.draft { all.append(draft) }
            for annotation in all {
                let color = AnnotationPalette[annotation.colorIndex]
                let p1 = CGPoint(x: annotation.start.x * sw, y: annotation.start.y * sh)
                let p2 = CGPoint(x: annotation.end.x * sw, y: annotation.end.y * sh)
                let rect = CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
                                  width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
                let stroke = Path { path in
                    switch annotation.kind {
                    case .rect: path.addRect(rect)
                    case .ellipse: path.addEllipse(in: rect)
                    case .arrow:
                        path.move(to: p1)
                        path.addLine(to: p2)
                    case .brush, .highlight: path.addRect(rect)
                    case .mosaic: path.addRect(rect)
                    case .text: path.addRect(rect)
                    }
                }
                let alpha: Double = annotation.kind == .highlight ? 0.4 : 1.0
                if annotation.kind == .highlight {
                    context.fill(stroke, with: .color(color.opacity(alpha)))
                } else if annotation.kind == .mosaic {
                    context.fill(stroke, with: .color(.gray.opacity(0.5)))
                } else if annotation.kind == .text {
                    let text = Text(annotation.text)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                    context.draw(text, at: p1, anchor: .topLeading)
                } else {
                    context.stroke(stroke, with: .color(color.opacity(alpha)), lineWidth: annotation.strokeWidth)
                }
            }
        }
    }
}

// MARK: - 工具按钮

private struct ToolIcon: View {
    let icon: String
    let kind: AnnotationKind?
    let state: AnnotationState
    var disabled = false
    let action: () -> Void

    @State private var hovering = false

    private var isActive: Bool {
        guard let kind else { return false }
        return state.activeKind == kind
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isActive ? Color(nsColor: .controlAccentColor) : (hovering ? .black : Color(red: 0.18, green: 0.18, blue: 0.22)))
            .opacity(disabled ? 0.35 : 1)
            .frame(width: 32, height: 32)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlAccentColor).opacity(0.15))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06))
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture { guard !disabled else { return }; action() }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
    }
}

struct SideTool: View {
    let icon: String
    let label: String
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(active ? Color(nsColor: .controlAccentColor) : .primary.opacity(hovering ? 0.08 : 0.05))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(active ? .white : .primary)
            }
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onHover { hovering = $0 }
        .onTapGesture { action() }
    }
}

/// 形状快捷按钮（面板中排）
struct ShapeQuick: View {
    let icon: String
    let kind: AnnotationKind
    let state: AnnotationState
    let action: () -> Void

    @State private var hovering = false

    private var isActive: Bool { state.activeKind == kind }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isActive ? Color(nsColor: .controlAccentColor) : .primary.opacity(0.75))
            .frame(width: 30, height: 30)
            .onHover { hovering = $0 }
            .scaleEffect(hovering ? 1.1 : 1)
            .onTapGesture { action() }
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovering)
    }
}

/// 马赛克/高亮开关行
struct ToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    let onChange: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.75))
                .frame(width: 22)
            Text(label).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: isOn) { _ in onChange() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.04)))
    }
}

/// OCR 结果行：文字 + 置信度，点按复制这行
struct OCRLineRow: View {
    let line: RecognizedText
    let onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.text)
                .font(.system(size: 13))
                .lineLimit(nil)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Text("\(Int(line.confidence * 100))%")
                .font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
                .padding(.top, 2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture {
            onCopy()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        }
        .overlay(alignment: .trailing) {
            if copied {
                Text("已复制")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
                    .padding(.trailing, 6)
            }
        }
        .help("点按复制这行")
    }
}

/// 翻译结果行：原文（小灰）+ 译文，点按复制译文
struct TranslationLineRow: View {
    let original: String
    let translated: String
    let onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(original)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .textSelection(.enabled)
            if translated.isEmpty {
                Text("这行翻译失败").font(.system(size: 13)).foregroundStyle(.red)
            } else {
                Text(translated)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(nil)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture {
            onCopy()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        }
        .help("点按复制译文")
    }
}

/// 面板里的小按钮（OCR / 翻译页签用）
struct MiniButton: View {
    let label: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(disabled ? 0.03 : 0.07)))
                .foregroundStyle(disabled ? .tertiary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - 文字标注输入框（NSTextField 包装：回车/失焦提交，Esc 取消）

/// Esc 键不走默认行为，交给 onEscape 处理，避免触发编辑器整体的 Esc 取消。
private final class CancelableTextField: NSTextField {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

private struct AnnotationTextField: NSViewRepresentable {
    var color: NSColor
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = CancelableTextField()
        field.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        field.textColor = color
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = color.withAlphaComponent(0.12)
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.layer?.borderColor = color.withAlphaComponent(0.5).cgColor
        field.layer?.borderWidth = 1
        let coordinator = context.coordinator
        field.onEscape = { [weak coordinator] in
            guard let coordinator, !coordinator.finished else { return }
            coordinator.finished = true
            onCancel()
        }
        // 入场即聚焦，等一帧让窗口完成布局
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onCommit: (String) -> Void
        var finished = false

        init(onCommit: @escaping (String) -> Void) {
            self.onCommit = onCommit
        }

        /// 回车与失焦都会走到这里；Esc 已在 keyDown 拦截，不会重复提交。
        func controlTextDidEndEditing(_ obj: Notification) {
            guard !finished, let field = obj.object as? NSTextField else { return }
            finished = true
            onCommit(field.stringValue)
        }
    }
}
