import SwiftUI
import CoreGraphics

/// 标注类型
enum AnnotationKind: CaseIterable {
    case rect, ellipse, arrow, brush, text, mosaic, highlight

    var icon: String {
        switch self {
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .brush: "pencil.tip"
        case .text: "textformat"
        case .mosaic: "square.grid.3x3.square"
        case .highlight: "drop"
        }
    }

    var label: String {
        switch self {
        case .rect: "矩形"
        case .ellipse: "椭圆"
        case .arrow: "箭头"
        case .brush: "画笔"
        case .text: "文字"
        case .mosaic: "马赛克"
        case .highlight: "高亮"
        }
    }
}

/// 单个标注：基于归一化坐标（0-1，相对选区）
struct Annotation: Identifiable {
    let id = UUID()
    var kind: AnnotationKind
    var start: CGPoint   // 归一化
    var end: CGPoint     // 归一化
    var colorIndex: Int
    var strokeWidth: CGFloat
    var text: String = ""
}

/// 标注颜色盘（参考图 7 色）
let AnnotationPalette: [Color] = [
    .red, .orange, .yellow, .blue, .purple, .black, .white
]

let AnnotationPaletteNS: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow, .systemBlue, .systemPurple, .black, .white
]

/// 编辑器状态
@Observable
@MainActor
final class AnnotationState {
    var annotations: [Annotation] = []
    var undoStack: [[Annotation]] = []
    var redoStack: [[Annotation]] = []
    var activeKind: AnnotationKind? = nil
    /// 标注色：记住上一次使用的颜色，下次截图继续沿用
    var colorIndex: Int {
        didSet { UserDefaults.standard.set(colorIndex, forKey: Self.colorIndexKey) }
    }
    var strokeWidth: CGFloat = 2
    var mosaicEnabled = false
    var highlightEnabled = false
    var draft: Annotation? = nil   // 正在绘制的
    /// 正在输入文字的标注落点（归一化坐标）；非 nil 时编辑器显示输入框
    var textEditingPoint: CGPoint? = nil
    /// 选择工具下被选中的标注（可拖动位置）
    var selectedAnnotationID: UUID? = nil

    private static let colorIndexKey = "lenso.annotation.colorIndex"

    init() {
        let saved = UserDefaults.standard.object(forKey: Self.colorIndexKey) as? Int ?? 3
        colorIndex = (0..<AnnotationPalette.count).contains(saved) ? saved : 3
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// 拖动标注前先压一次快照，整段拖动只产生一步撤销
    func snapshotForInteraction() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    /// 选区变化（移动/缩放）时重算标注的归一化坐标：
    /// 让标注始终钉在画面内容上，而不是相对选区被拉伸变形。
    func remapAnnotations(from old: CGRect, to new: CGRect) {
        guard old != new, old.width > 0, old.height > 0, new.width > 0, new.height > 0 else { return }
        for index in annotations.indices {
            let start = CGPoint(
                x: old.minX + annotations[index].start.x * old.width,
                y: old.minY + annotations[index].start.y * old.height
            )
            let end = CGPoint(
                x: old.minX + annotations[index].end.x * old.width,
                y: old.minY + annotations[index].end.y * old.height
            )
            annotations[index].start = CGPoint(
                x: (start.x - new.minX) / new.width,
                y: (start.y - new.minY) / new.height
            )
            annotations[index].end = CGPoint(
                x: (end.x - new.minX) / new.width,
                y: (end.y - new.minY) / new.height
            )
            // 文字是固定字号渲染的，包围盒按新选区重算，避免拖动热区/选中框对不上
            if annotations[index].kind == .text, !annotations[index].text.isEmpty {
                let font = NSFont.systemFont(ofSize: 16, weight: .semibold)
                let size = NSAttributedString(
                    string: annotations[index].text,
                    attributes: [.font: font]
                ).size()
                annotations[index].end = CGPoint(
                    x: annotations[index].start.x + size.width / new.width,
                    y: annotations[index].start.y + size.height / new.height
                )
            }
        }
    }

    /// 绝对定位某条标注（拖动时按起点快照计算，避免逐帧累积误差），并夹在选区内
    func setPositions(id: UUID, start: CGPoint, end: CGPoint) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let minX = min(start.x, end.x), maxX = max(start.x, end.x)
        let minY = min(start.y, end.y), maxY = max(start.y, end.y)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if minX < 0 { dx = -minX } else if maxX > 1 { dx = 1 - maxX }
        if minY < 0 { dy = -minY } else if maxY > 1 { dy = 1 - maxY }
        annotations[index].start = CGPoint(x: start.x + dx, y: start.y + dy)
        annotations[index].end = CGPoint(x: end.x + dx, y: end.y + dy)
    }

    func push(_ annotation: Annotation) {
        undoStack.append(annotations)
        redoStack.removeAll()
        annotations.append(annotation)
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = last
    }

    func redo() {
        guard let last = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = last
    }

    func reset() {
        annotations = []
        undoStack = []
        redoStack = []
        draft = nil
        textEditingPoint = nil
        selectedAnnotationID = nil
    }
}

/// 统一标注渲染器：供完整截图编辑器及贴图浮窗使用
@MainActor
enum AnnotationRenderer {
    static func drawArrow(_ ctx: CGContext, from: CGPoint, to: CGPoint, headLen: CGFloat) {
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
        let angle = atan2(to.y - from.y, to.x - from.x)
        for delta in [0.42, -0.42] {
            let hx = to.x - headLen * cos(angle + delta)
            let hy = to.y - headLen * sin(angle + delta)
            ctx.move(to: to)
            ctx.addLine(to: CGPoint(x: hx, y: hy))
            ctx.strokePath()
        }
    }

    static func applyMosaic(_ ctx: CGContext, image: CGImage, rect: CGRect, scale: CGFloat = 1.0) {
        let blockSize = max(8, Int(16 * scale) / 2)
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

    static func drawSingleAnnotation(
        _ annotation: Annotation,
        in ctx: CGContext,
        size: CGSize,
        baseImage: CGImage? = nil,
        scale: CGFloat = 1.0
    ) {
        let sw = size.width
        let sh = size.height
        let color = NSColor(AnnotationPalette[annotation.colorIndex]).withAlphaComponent(annotation.kind == .highlight ? 0.4 : 1.0)
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(annotation.strokeWidth * scale)
        ctx.setLineCap(.round)

        let p1 = CGPoint(x: annotation.start.x * sw, y: annotation.start.y * sh)
        let p2 = CGPoint(x: annotation.end.x * sw, y: annotation.end.y * sh)
        let rect = CGRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )

        switch annotation.kind {
        case .rect:
            ctx.stroke(rect)
        case .ellipse:
            ctx.strokeEllipse(in: rect)
        case .arrow:
            drawArrow(ctx, from: p1, to: p2, headLen: 12 * scale)
        case .brush:
            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.strokePath()
        case .highlight:
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        case .mosaic:
            if let baseImage {
                applyMosaic(ctx, image: baseImage, rect: rect, scale: scale)
            } else {
                ctx.setFillColor(NSColor.gray.withAlphaComponent(0.5).cgColor)
                ctx.fill(rect)
            }
        case .text:
            guard !annotation.text.isEmpty else { return }
            let fontSize = max(12, 14 * scale)
            let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(AnnotationPalette[annotation.colorIndex])
            ]
            let attr = NSAttributedString(string: annotation.text, attributes: attrs)
            let topDownRect = CGRect(
                x: min(p1.x, p2.x),
                y: min(p1.y, p2.y),
                width: max(1, rect.width),
                height: max(fontSize * 1.3, rect.height)
            )
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            attr.draw(in: topDownRect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func renderAnnotations(
        _ annotations: [Annotation],
        onto base: CGImage
    ) -> CGImage {
        guard !annotations.isEmpty else { return base }
        let w = base.width
        let h = base.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }

        // CoreGraphics 默认坐标原点在左下角，绘制前先转换为左上角为原点
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1.0, y: -1.0)

        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))

        let scale = max(1.0, CGFloat(w) / 600.0)
        let size = CGSize(width: w, height: h)
        for ann in annotations {
            drawSingleAnnotation(ann, in: ctx, size: size, baseImage: base, scale: scale)
        }

        return ctx.makeImage() ?? base
    }
}
