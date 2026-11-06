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
    let onPin: (CGImage) -> Void

    @State private var state = AnnotationState()
    @State private var selection: CGRect
    @State private var draggingHandle: SelectionHandle? = nil
    @State private var drawingAnnotation = false

    /// 冻结图与屏幕的像素比
    private var imageScale: CGFloat {
        CGFloat(frozenImage.width) / screenFrame.width
    }

    init(frozenImage: CGImage, screenFrame: CGRect, initialSelection: CGRect,
         onComplete: @escaping (CGImage?) -> Void,
         onQuickCopy: @escaping (CGImage) -> Void,
         onPin: @escaping (CGImage) -> Void) {
        self.frozenImage = frozenImage
        self.screenFrame = screenFrame
        self.initialSelection = initialSelection
        self.onComplete = onComplete
        self.onQuickCopy = onQuickCopy
        self.onPin = onPin
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        ZStack {
            // 冻结画面
            Image(decorative: frozenImage, scale: 1)
                .resizable()
                .frame(width: screenFrame.width, height: screenFrame.height)
                .position(x: screenFrame.midX - screenFrame.origin.x, y: screenFrame.midY - screenFrame.origin.y)
                .allowsHitTesting(false)

            // 选区内容视图（挖空 + 标注渲染）
            SelectionContent(
                frozenImage: frozenImage,
                screenFrame: screenFrame,
                selection: selection,
                state: state,
                imageScale: imageScale,
                onSelectionChange: { selection = $0 },
                onDragHandle: { draggingHandle = $0 },
                draggingHandle: draggingHandle
            )

            // 工具栏：紧贴选区下方（随选区移动），右侧属性面板紧贴选区右侧
            toolbarAndPanel
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .background(Color.black.opacity(0.001)) // 接管点击
        .onExitCommand { discard() }           // Esc 取消
    }

    /// 丢弃本次截图
    private func discard() {
        onComplete(nil)
    }

    /// 钉图：合成后交给 Coordinator 浮在屏幕上
    private func pinImage() {
        guard let composited = renderFinalImage() else { return }
        onPin(composited)
    }

    /// 工具栏挂在选区下边缘中点；属性面板挂在选区右侧垂直居中
    @ViewBuilder
    private var toolbarAndPanel: some View {
        let localSel = CGRect(
            x: selection.origin.x - screenFrame.origin.x,
            y: selection.origin.y - screenFrame.origin.y,
            width: selection.width, height: selection.height
        )
        // 工具栏位置：选区下方 12pt，横向居中于选区（越界时往屏内收）
        let toolbarSize = CGSize(width: 720, height: 52)
        let toolbarX = min(
            max(toolbarSize.width / 2 + 8, localSel.midX),
            screenFrame.width - toolbarSize.width / 2 - 8
        )
        let toolbarY = min(localSel.maxY + 14 + toolbarSize.height / 2, screenFrame.height - toolbarSize.height / 2 - 8)
        // 面板位置：选区右侧 16pt，垂直居中于选区（越界时往屏内收）
        let panelSize = CGSize(width: 252, height: 470)
        let panelX = min(localSel.maxX + 16 + panelSize.width / 2, screenFrame.width - panelSize.width / 2 - 8)
        let panelY = min(
            max(panelSize.height / 2 + 8, localSel.midY),
            screenFrame.height - panelSize.height / 2 - 8
        )

        Group {
            bottomToolbar
                .frame(width: toolbarSize.width)
                .position(x: toolbarX, y: toolbarY)

            sidePanel
                .frame(width: panelSize.width)
                .position(x: panelX, y: panelY)
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
                    .foregroundStyle(state.activeKind == nil ? .white : .secondary)
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

            // 钉图：把当前合成结果钉在屏幕最上层
            Image(systemName: "pin.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.primary.opacity(0.07)))
                .contentShape(Rectangle())
                .onTapGesture { discard() }
                .help("取消截图（Esc）")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if #available(macOS 26.0, *) {
                Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
    }

    // MARK: - 右侧属性面板（严格对齐参考图 3）

    private var sidePanel: some View {
        VStack(spacing: 14) {
            // 顶部工具行：标注 / 翻译 / OCR / 更多（图标圆底）
            HStack(spacing: 20) {
                SideTool(icon: "highlighter", label: "标注", active: state.activeKind != nil) {
                    state.activeKind = .brush
                }
                SideTool(icon: "character.bubble", label: "翻译", active: false) {}
                SideTool(icon: "doc.text.viewfinder", label: "OCR", active: false) {}
                SideTool(icon: "ellipsis", label: "更多", active: false) {}
            }

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
        .padding(16)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
    }

    // MARK: - Actions

    private func finishEditing() {
        let composited = renderFinalImage()
        onComplete(composited)
    }

    private func quickCopy() {
        let composited = renderFinalImage()
        guard let composited else { return }
        onQuickCopy(composited)
    }

    /// 合成：冻结帧裁剪选区 + 标注
    private func renderFinalImage() -> CGImage? {
        let pxRect = CGRect(
            x: (selection.origin.x - screenFrame.origin.x) * imageScale,
            y: (selection.origin.y - screenFrame.origin.y) * imageScale,
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
                // MVP：文字标注画为半透明底色块（正式版接入 NSTextField 输入）
                ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(0.5).cgColor)
                ctx.fill(rect)
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

// MARK: - 选区内容（挖空 + 手柄 + 标注绘制接收鼠标）

enum SelectionHandle {
    case topLeft, topRight, bottomLeft, bottomRight
    case topEdge, bottomEdge, leftEdge, rightEdge
}

private struct SelectionContent: View {
    let frozenImage: CGImage
    let screenFrame: CGRect
    let selection: CGRect
    let state: AnnotationState
    let imageScale: CGFloat
    let onSelectionChange: (CGRect) -> Void
    let onDragHandle: (SelectionHandle?) -> Void
    let draggingHandle: SelectionHandle?

    @State private var dragOrigin: CGPoint? = nil
    @State private var selectionOrigin: CGRect? = nil

    var body: some View {
        // 暗幕层（全屏，选区挖空）
        Canvas { context, size in
            let localSel = CGRect(
                x: selection.origin.x - screenFrame.origin.x,
                y: selection.origin.y - screenFrame.origin.y,
                width: selection.width, height: selection.height
            )
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.3)))
            context.blendMode = .clear
            context.fill(Path(localSel), with: .color(.white))
            context.blendMode = .normal
            context.stroke(Path(localSel), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .position(x: screenFrame.midX - screenFrame.origin.x, y: screenFrame.midY - screenFrame.origin.y)
        .overlay {
            // 选区内部：标注绘制画布 + 选中图像预览
            // 仅在选中标注工具时才消费拖拽（否则拖拽用于移动选区）
            SelectionInner(
                frozenImage: frozenImage,
                screenFrame: screenFrame,
                selection: selection,
                state: state,
                imageScale: imageScale
            )
            .frame(width: selection.width, height: selection.height)
            .position(
                x: selection.midX - screenFrame.origin.x,
                y: selection.midY - screenFrame.origin.y
            )
            .contentShape(Rectangle())
            .gesture(annotationGesture, including: state.activeKind != nil ? .all : .subviews)
        }
        .overlay {
            // 八个手柄
            handles
        }
        .contentShape(Rectangle())
        .gesture(adjustGesture)
    }

    // MARK: 手柄

    private var handles: some View {
        ForEach(handlePositions, id: \.0) { handle, point in
            RoundedRectangle(cornerRadius: handle == .topEdge || handle == .bottomEdge || handle == .leftEdge || handle == .rightEdge ? 2 : 6)
                .fill(.white)
                .frame(width: handleSize(for: handle).width, height: handleSize(for: handle).height)
                .shadow(radius: 2)
                .position(point)
                .onTapGesture { onDragHandle(handle) }
        }
    }

    private var handlePositions: [(SelectionHandle, CGPoint)] {
        let sel = selection
        return [
            (.topLeft, CGPoint(x: sel.minX - screenFrame.origin.x, y: sel.minY - screenFrame.origin.y)),
            (.topRight, CGPoint(x: sel.maxX - screenFrame.origin.x, y: sel.minY - screenFrame.origin.y)),
            (.bottomLeft, CGPoint(x: sel.minX - screenFrame.origin.x, y: sel.maxY - screenFrame.origin.y)),
            (.bottomRight, CGPoint(x: sel.maxX - screenFrame.origin.x, y: sel.maxY - screenFrame.origin.y)),
            (.topEdge, CGPoint(x: sel.midX - screenFrame.origin.x, y: sel.minY - screenFrame.origin.y)),
            (.bottomEdge, CGPoint(x: sel.midX - screenFrame.origin.x, y: sel.maxY - screenFrame.origin.y)),
            (.leftEdge, CGPoint(x: sel.minX - screenFrame.origin.x, y: sel.midY - screenFrame.origin.y)),
            (.rightEdge, CGPoint(x: sel.maxX - screenFrame.origin.x, y: sel.midY - screenFrame.origin.y)),
        ]
    }

    private func handleSize(for handle: SelectionHandle) -> CGSize {
        switch handle {
        case .topEdge, .bottomEdge: CGSize(width: 18, height: 6)
        case .leftEdge, .rightEdge: CGSize(width: 6, height: 18)
        default: CGSize(width: 11, height: 11)
        }
    }

    // MARK: 手势

    private var adjustGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = value.startLocation
                    selectionOrigin = selection
                }
                let delta = CGPoint(x: value.location.x - dragOrigin!.x, y: value.location.y - dragOrigin!.y)
                let newSel = adjustedSelection(handle: draggingHandle, origin: selectionOrigin!, delta: delta)
                onSelectionChange(newSel)
            }
            .onEnded { _ in
                dragOrigin = nil
                selectionOrigin = nil
                onDragHandle(nil)
            }
    }

    private func adjustedSelection(handle: SelectionHandle?, origin: CGRect, delta: CGPoint) -> CGRect {
        guard let handle else {
            return origin.offsetBy(dx: delta.x, dy: delta.y)
        }
        var s = origin
        switch handle {
        case .topLeft:
            s = CGRect(x: origin.minX + delta.x, y: origin.minY + delta.y,
                       width: origin.width - delta.x, height: origin.height - delta.y)
        case .topRight:
            s = CGRect(x: origin.minX, y: origin.minY + delta.y,
                       width: origin.width + delta.x, height: origin.height - delta.y)
        case .bottomLeft:
            s = CGRect(x: origin.minX + delta.x, y: origin.minY,
                       width: origin.width - delta.x, height: origin.height + delta.y)
        case .bottomRight:
            s = CGRect(x: origin.minX, y: origin.minY,
                       width: origin.width + delta.x, height: origin.height + delta.y)
        case .topEdge:
            s = CGRect(x: origin.minX, y: origin.minY + delta.y, width: origin.width, height: origin.height - delta.y)
        case .bottomEdge:
            s = CGRect(x: origin.minX, y: origin.minY, width: origin.width, height: origin.height + delta.y)
        case .leftEdge:
            s = CGRect(x: origin.minX + delta.x, y: origin.minY, width: origin.width - delta.x, height: origin.height)
        case .rightEdge:
            s = CGRect(x: origin.minX, y: origin.minY, width: origin.width + delta.x, height: origin.height)
        }
        return s.standardized
    }

    private var annotationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard let kind = state.activeKind else { return }
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
            x: startLocal.x - (selection.origin.x),
            y: startLocal.y - (selection.origin.y)
        )
        let innerCurrent = CGPoint(
            x: current.x - (selection.origin.x),
            y: current.y - (selection.origin.y)
        )
        func norm(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(1, max(0, p.x / max(1, selection.width))),
                    y: min(1, max(0, p.y / max(1, selection.height))))
        }
        return (norm(innerStart), norm(innerCurrent))
    }
}

// MARK: - 选区内部（图像预览 + 标注渲染）

private struct SelectionInner: View {
    let frozenImage: CGImage
    let screenFrame: CGRect
    let selection: CGRect
    let state: AnnotationState
    let imageScale: CGFloat

    var body: some View {
        ZStack {
            // 选区原图预览
            let pxRect = CGRect(
                x: (selection.origin.x - screenFrame.origin.x) * imageScale,
                y: (selection.origin.y - screenFrame.origin.y) * imageScale,
                width: selection.width * imageScale,
                height: selection.height * imageScale
            ).integral
            if let cropped = frozenImage.cropping(to: pxRect) {
                Image(decorative: cropped, scale: 1)
                    .resizable()
                    .frame(width: selection.width, height: selection.height)
            }

            // 标注层
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
                        context.fill(stroke, with: .color(.gray.opacity(0.5))) // 预览占位；导出时真马赛克
                    } else if annotation.kind == .text {
                        context.fill(stroke, with: .color(.yellow.opacity(0.5)))
                    } else {
                        context.stroke(stroke, with: .color(color.opacity(alpha)), lineWidth: annotation.strokeWidth)
                    }
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
            .foregroundStyle(isActive ? Color(nsColor: .controlAccentColor) : (hovering ? .primary : .secondary))
            .opacity(disabled ? 0.35 : 1)
            .frame(width: 32, height: 32)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlAccentColor).opacity(0.15))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.06))
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture { guard !disabled else { return }; action() }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
    }
}

private struct SideTool: View {
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
private struct ShapeQuick: View {
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
private struct ToggleRow: View {
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
