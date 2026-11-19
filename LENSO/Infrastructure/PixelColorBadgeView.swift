import AppKit

/// 光标色值提示：不做放大镜，只在光标旁显示当前像素的十六进制色码。
/// 每次移动从冻结帧裁 1×1 像素读取颜色，开销可以忽略。
final class PixelColorBadgeView: NSView {
    private let swatch = NSView()
    private let label = NSTextField(labelWithString: "#000000")
    private var frozenImage: CGImage?

    nonisolated(unsafe) private let pixelBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
    private lazy var sampleContext: CGContext? = CGContext(
        data: pixelBuffer,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 3
        swatch.layer?.borderWidth = 0.5
        swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        addSubview(swatch)

        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        pixelBuffer.deallocate()
    }

    func setFrozenImage(_ image: CGImage) {
        frozenImage = image
    }

    func hide() {
        isHidden = true
    }

    /// 光标位于面板内的坐标（左下原点）
    func update(cursor: CGPoint, panelSize: CGSize) {
        guard let image = frozenImage, panelSize.width > 1, panelSize.height > 1,
              let color = sampleColor(at: cursor, panelSize: panelSize, image: image) else {
            isHidden = true
            return
        }

        label.stringValue = color.hex
        swatch.layer?.backgroundColor = color.nsColor.cgColor

        // 胶囊尺寸随色值宽度变化（#RRGGBB 是等宽的，但保留自适应更稳）
        label.sizeToFit()
        let height: CGFloat = 24
        let swatchSize: CGFloat = 12
        let padding: CGFloat = 8
        let width = padding + swatchSize + 6 + label.frame.width + padding
        label.frame = CGRect(
            x: padding + swatchSize + 6,
            y: (height - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )
        swatch.frame = CGRect(
            x: padding,
            y: (height - swatchSize) / 2,
            width: swatchSize,
            height: swatchSize
        )

        // 默认在光标右上，贴边时翻到另一侧，且不越出屏幕
        var origin = CGPoint(x: cursor.x + 16, y: cursor.y + 16)
        if origin.x + width > panelSize.width - 6 { origin.x = cursor.x - width - 16 }
        if origin.y + height > panelSize.height - 6 { origin.y = cursor.y - height - 16 }
        origin.x = min(max(6, origin.x), max(6, panelSize.width - width - 6))
        origin.y = min(max(6, origin.y), max(6, panelSize.height - height - 6))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = CGRect(origin: origin, size: CGSize(width: width, height: height))
        CATransaction.commit()

        isHidden = false
    }

    // MARK: - 取色

    private struct SampledColor {
        let hex: String
        let nsColor: NSColor
    }

    private func sampleColor(at cursor: CGPoint, panelSize: CGSize, image: CGImage) -> SampledColor? {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        guard imageWidth >= 1, imageHeight >= 1 else { return nil }

        // 面板坐标 → 像素坐标（CGImage 以左上角为原点）
        let px = min(max(0, Int(cursor.x / panelSize.width * imageWidth)), image.width - 1)
        let py = min(max(0, Int((1 - cursor.y / panelSize.height) * imageHeight)), image.height - 1)

        guard let crop = image.cropping(to: CGRect(x: px, y: py, width: 1, height: 1)),
              let context = sampleContext else {
            return nil
        }
        context.interpolationQuality = .none
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = pixelBuffer[0], g = pixelBuffer[1], b = pixelBuffer[2]
        let value = String(format: "#%02X%02X%02X", r, g, b)
        let color = NSColor(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
        return SampledColor(hex: value, nsColor: color)
    }
}
