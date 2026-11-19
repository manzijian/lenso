import AppKit
import CoreGraphics

// MARK: - 标注工具与颜色

/// 原地标注工具（顺序与工具栏一致）
enum AnnotationTool: CaseIterable {
    case arrow, rect, ellipse, brush, text, mosaic

    var symbolName: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .brush: "pencil.tip"
        case .text: "textformat"
        case .mosaic: "square.grid.3x3"
        }
    }

    var label: String {
        switch self {
        case .arrow: "箭头"
        case .rect: "矩形"
        case .ellipse: "椭圆"
        case .brush: "画笔"
        case .text: "文字"
        case .mosaic: "马赛克"
        }
    }

    /// 与设计稿一致的快捷键提示（仅用于 tooltip）
    var shortcutHint: String {
        switch self {
        case .arrow: "⌘1"
        case .rect: "⌘2"
        case .ellipse: "⌘3"
        case .brush: "⌘4"
        case .text: "⌘5"
        case .mosaic: "⌘6"
        }
    }
}

enum AnnotationInk {
    static let blue = NSColor(srgbRed: 5 / 255, green: 56 / 255, blue: 224 / 255, alpha: 1)

    /// 颜色弹层的 5 个颜色（红、橙、蓝、绿、墨黑）
    static let palette: [NSColor] = [
        NSColor(srgbRed: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 1),
        NSColor(srgbRed: 245 / 255, green: 165 / 255, blue: 36 / 255, alpha: 1),
        blue,
        NSColor(srgbRed: 18 / 255, green: 161 / 255, blue: 80 / 255, alpha: 1),
        NSColor(srgbRed: 20 / 255, green: 22 / 255, blue: 27 / 255, alpha: 1)
    ]

    /// 3 档粗细（单位：屏幕点）
    static let widths: [CGFloat] = [1.5, 3, 5]
}

/// 单条标注：坐标是画布本地坐标（屏幕点，原点左上）
struct AnnotationMark {
    let id = UUID()
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    /// 画笔轨迹
    var points: [CGPoint] = []
    var color: NSColor
    var lineWidth: CGFloat
    var text: String = ""
}

// MARK: - 选区内的标注画布

/// 覆盖在选区上的透明画布：接收鼠标绘制、显示标注、并把标注按原图像素合成导出。
/// 坐标统一为「选区本地、原点左上」（view 为 flipped），导出时按 baseImage / bounds 的比例缩放。
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    /// 选区原图（物理像素，已裁剪）
    var baseImage: CGImage? {
        didSet { needsDisplay = true }
    }

    /// 图像像素 / 屏幕点
    let imageScale: CGFloat

    var tool: AnnotationTool = .arrow
    var color: NSColor = AnnotationInk.blue
    var lineWidth: CGFloat = 3

    private(set) var marks: [AnnotationMark] = []
    private var draft: AnnotationMark?
    private var activeTextField: NSTextField?
    private var textAnchor: CGPoint?
    private var isTearingDownTextField = false

    var onMarksChanged: (() -> Void)?
    var onTextEditingChanged: ((Bool) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    init(frame: NSRect, baseImage: CGImage?, imageScale: CGFloat) {
        self.baseImage = baseImage
        self.imageScale = max(1, imageScale)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - 状态

    var isEditingText: Bool { activeTextField != nil }

    func undo() {
        cancelTextEditing()
        guard !marks.isEmpty else { return }
        marks.removeLast()
        needsDisplay = true
        onMarksChanged?()
    }

    /// 提交正在输入的文字（完成/复制/贴图前调用）
    func commitPendingText() {
        commitTextEditing()
    }

    func cancelTextEditing() {
        guard let field = activeTextField else { return }
        isTearingDownTextField = true
        field.removeFromSuperview()
        activeTextField = nil
        textAnchor = nil
        isTearingDownTextField = false
        window?.makeFirstResponder(nil)
        onTextEditingChanged?(false)
    }

    private func commitTextEditing() {
        guard let field = activeTextField, let anchor = textAnchor else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        isTearingDownTextField = true
        field.removeFromSuperview()
        activeTextField = nil
        textAnchor = nil
        isTearingDownTextField = false
        window?.makeFirstResponder(nil)
        onTextEditingChanged?(false)
        guard !trimmed.isEmpty else { return }

        let font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let measured = NSAttributedString(string: trimmed, attributes: [.font: font]).size()
        let end = CGPoint(
            x: min(bounds.width, anchor.x + measured.width),
            y: min(bounds.height, anchor.y + measured.height)
        )
        marks.append(AnnotationMark(
            tool: .text, start: anchor, end: end,
            color: color, lineWidth: lineWidth, text: trimmed
        ))
        needsDisplay = true
        onMarksChanged?()
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        // 有输入框时，第一次点击只负责收起输入框，避免误画
        if isEditingText {
            commitTextEditing()
            return
        }

        let point = clamp(convert(event.locationInWindow, from: nil))
        if tool == .text {
            beginTextEditing(at: point)
            return
        }

        draft = AnnotationMark(
            tool: tool, start: point, end: point,
            points: tool == .brush ? [point] : [],
            color: color, lineWidth: lineWidth
        )
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var draft else { return }
        let point = clamp(convert(event.locationInWindow, from: nil))
        draft.end = point
        if draft.tool == .brush {
            draft.points.append(point)
        }
        self.draft = draft
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let draft else { return }
        self.draft = nil

        if draft.tool == .brush {
            if draft.points.count > 1, totalLength(of: draft.points) > 2 {
                marks.append(draft)
                onMarksChanged?()
            }
        } else {
            let dx = abs(draft.end.x - draft.start.x)
            let dy = abs(draft.end.y - draft.start.y)
            if dx > 3 || dy > 3 {
                marks.append(draft)
                onMarksChanged?()
            }
        }
        needsDisplay = true
    }

    private func beginTextEditing(at point: CGPoint) {
        let fieldWidth: CGFloat = 240
        let x = min(max(0, point.x), max(0, bounds.width - fieldWidth - 4))
        let field = NSTextField(frame: NSRect(x: x, y: point.y, width: fieldWidth, height: 28))
        field.font = .systemFont(ofSize: 16, weight: .semibold)
        field.textColor = color
        field.backgroundColor = NSColor.white.withAlphaComponent(0.94)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.placeholderString = "输入文字"
        field.delegate = self
        addSubview(field)
        activeTextField = field
        textAnchor = point
        window?.makeFirstResponder(field)
        onTextEditingChanged?(true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextEditing()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isTearingDownTextField else { return }
        commitTextEditing()
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for mark in marks {
            draw(mark, in: ctx)
        }
        if let draft {
            draw(draft, in: ctx)
        }
    }

    private func draw(_ mark: AnnotationMark, in ctx: CGContext) {
        switch mark.tool {
        case .mosaic:
            drawMosaic(in: viewRect(for: mark), ctx: ctx, base: baseImage, scale: imageScale)
        case .text:
            drawText(mark, in: ctx, scale: 1)
        case .arrow, .rect, .ellipse, .brush:
            ctx.saveGState()
            ctx.setStrokeColor(mark.color.cgColor)
            ctx.setFillColor(mark.color.cgColor)
            ctx.setLineWidth(mark.lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            drawStroke(mark, in: ctx, scale: 1)
            ctx.restoreGState()
        }
    }

    private func drawStroke(_ mark: AnnotationMark, in ctx: CGContext, scale: CGFloat) {
        let start = CGPoint(x: mark.start.x * scale, y: mark.start.y * scale)
        let end = CGPoint(x: mark.end.x * scale, y: mark.end.y * scale)
        switch mark.tool {
        case .rect:
            ctx.stroke(rectBetween(start, end))
        case .ellipse:
            ctx.strokeEllipse(in: rectBetween(start, end))
        case .arrow:
            drawArrow(ctx, from: start, to: end, headLen: max(10, mark.lineWidth * 4.2) * scale)
        case .brush:
            let points = mark.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
            guard let first = points.first else { return }
            if points.count == 1 {
                let r = max(0.75, mark.lineWidth / 2) * scale
                ctx.fillEllipse(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
            } else {
                ctx.move(to: first)
                for point in points.dropFirst() {
                    ctx.addLine(to: point)
                }
                ctx.strokePath()
            }
        default:
            break
        }
    }

    private func drawArrow(_ ctx: CGContext, from: CGPoint, to: CGPoint, headLen: CGFloat) {
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

    private func drawText(_ mark: AnnotationMark, in ctx: CGContext, scale: CGFloat) {
        guard !mark.text.isEmpty else { return }
        let fontSize = 16 * scale
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: mark.color
        ]
        let attr = NSAttributedString(string: mark.text, attributes: attrs)
        let origin = CGPoint(x: mark.start.x * scale, y: mark.start.y * scale)
        let rect = CGRect(
            x: origin.x,
            y: origin.y,
            width: max(1, (mark.end.x - mark.start.x) * scale + fontSize),
            height: max(fontSize * 1.35, (mark.end.y - mark.start.y) * scale + fontSize)
        )
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        attr.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 马赛克：从选区原图裁一小块、低分辨率重采样，再用最近邻填回目标矩形。
    private func drawMosaic(in rect: CGRect, ctx: CGContext, base: CGImage?, scale: CGFloat) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        guard let base, let small = pixelatedImage(from: base, rect: rect, scale: scale) else {
            // 原图尚未到位时先盖一层灰，保证操作有可见反馈
            ctx.saveGState()
            ctx.setFillColor(NSColor.gray.withAlphaComponent(0.5).cgColor)
            ctx.fill(rect)
            ctx.restoreGState()
            return
        }
        let smallSize = NSSize(width: small.width, height: small.height)
        let nsImage = NSImage(cgImage: small, size: smallSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        ctx.saveGState()
        ctx.clip(to: [rect])
        ctx.interpolationQuality = .none
        nsImage.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func pixelatedImage(from base: CGImage, rect: CGRect, scale: CGFloat) -> CGImage? {
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        let imageBounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let cropRect = pixelRect.intersection(imageBounds).integral
        guard cropRect.width >= 1, cropRect.height >= 1,
              let crop = base.cropping(to: cropRect) else { return nil }

        let block = max(6, Int(8 * scale))
        let smallW = max(1, Int(cropRect.width) / block)
        let smallH = max(1, Int(cropRect.height) / block)
        guard let smallCtx = CGContext(
            data: nil, width: smallW, height: smallH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        smallCtx.interpolationQuality = .low
        smallCtx.draw(crop, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        return smallCtx.makeImage()
    }

    // MARK: - 导出

    /// 把原图与所有已提交标注合成为一张图；坐标按 图像像素 / 画布点 的比例缩放。
    func renderFinalImage(from base: CGImage) -> CGImage {
        guard !marks.isEmpty else { return base }
        let width = base.width
        let height = base.height
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }

        // CGContext 默认原点左下；翻成左上原点，和画布坐标一致
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let scale = CGFloat(width) / max(1, bounds.width)
        for mark in marks {
            switch mark.tool {
            case .mosaic:
                drawMosaic(
                    in: viewRect(for: mark, scale: scale),
                    ctx: ctx,
                    base: base,
                    scale: CGFloat(base.width) / max(1, bounds.width)
                )
            case .text:
                drawText(mark, in: ctx, scale: scale)
            case .arrow, .rect, .ellipse, .brush:
                ctx.saveGState()
                ctx.setStrokeColor(mark.color.cgColor)
                ctx.setFillColor(mark.color.cgColor)
                ctx.setLineWidth(mark.lineWidth * scale)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                drawStroke(mark, in: ctx, scale: scale)
                ctx.restoreGState()
            }
        }
        return ctx.makeImage() ?? base
    }

    // MARK: - 几何辅助

    private func viewRect(for mark: AnnotationMark, scale: CGFloat = 1) -> CGRect {
        rectBetween(
            CGPoint(x: mark.start.x * scale, y: mark.start.y * scale),
            CGPoint(x: mark.end.x * scale, y: mark.end.y * scale)
        )
    }

    private func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(b.x - a.x), height: abs(b.y - a.y)
        )
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), max(0, bounds.width)),
            y: min(max(0, point.y), max(0, bounds.height))
        )
    }

    private func totalLength(of points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for index in 1..<points.count {
            total += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }
        return total
    }
}
