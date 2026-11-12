import AppKit
import SwiftUI

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

struct SelectionContent: View {
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

struct SelectionInner: View {
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
