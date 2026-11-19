import AppKit
import CoreGraphics
import SwiftUI

// MARK: - 截图编辑器最终合成渲染扩展

extension CaptureEditorView {
    /// 合成：冻结帧裁剪选区 + 标注
    func renderFinalImage() -> CGImage? {
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

    func drawArrow(_ ctx: CGContext, from: CGPoint, to: CGPoint, headLen: CGFloat) {
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

    /// 马赛克：把目标区域压成低分辨率再按最近邻放大，得到块状像素
    func applyMosaic(_ ctx: CGContext, image: CGImage, rect: CGRect) {
        let blockPx = max(6, 14 * imageScale)
        // 上下文坐标原点在左下，CGImage 裁剪原点在左上，先换算
        let crop = CGRect(
            x: rect.minX,
            y: CGFloat(image.height) - rect.maxY,
            width: rect.width,
            height: rect.height
        ).integral
        guard crop.width >= 1, crop.height >= 1,
              let region = image.cropping(to: crop) else { return }

        let smallW = max(1, Int(crop.width / blockPx))
        let smallH = max(1, Int(crop.height / blockPx))
        guard let smallCtx = CGContext(
            data: nil, width: smallW, height: smallH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        smallCtx.interpolationQuality = .medium
        smallCtx.draw(region, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let small = smallCtx.makeImage() else { return }

        ctx.saveGState()
        ctx.clip(to: [rect])
        ctx.interpolationQuality = .none
        ctx.draw(small, in: rect)
        ctx.restoreGState()
    }
}
