import AppKit

// MARK: - 贴图右上角极速响应关闭按钮

final class PinnedCloseButton: NSButton {
    var onClick: (() -> Void)?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        // 瞬间响应：鼠标按下瞬间立即触发关闭，无需等待 mouseUp，0 延迟秒关
        onClick?()
    }
}

// MARK: - 贴图展示及标注交互视图

final class PinnedImageView: NSView, NSTextFieldDelegate {
    let image: CGImage
    let state: AnnotationState
    var onClose: (() -> Void)?
    var onToggleEditing: (() -> Void)?
    var onWindowMovedOrResized: (() -> Void)?

    private let closeButton = PinnedCloseButton()
    private var tracking: NSTrackingArea?
    private let baseSize: NSSize
    private var currentScale: CGFloat = max(0.4, min(AppSettings.shared.previewScale, 5.0))

    // 文字标注临时输入框
    private var activeTextField: NSTextField?
    private var textStartNormPoint: CGPoint?

    // 窗口平滑拖拽与双击判定（不使用阻塞的 performDrag，避免吞掉第二次点击）
    private var initialMouseScreenLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private var isDraggingWindow = false

    override var isFlipped: Bool { true }

    init(frame: NSRect, image: CGImage, state: AnnotationState) {
        self.image = image
        self.state = state
        self.baseSize = frame.size
        super.init(frame: frame)
        toolTip = "左键拖拽移动 · 滚轮缩放 · 右键/空格唤出编辑栏 · 双击或点击右上角✕关闭"

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 12
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        closeButton.attributedTitle = NSAttributedString(
            string: "✕",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .bold)
            ]
        )
        closeButton.onClick = { [weak self] in
            self?.onClose?()
        }
        closeButton.toolTip = "关闭贴图 (Esc / ⌘W / 双击)"
        closeButton.isHidden = false
        closeButton.alphaValue = 0.85
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func closeClicked() { onClose?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 绘制原底图
        let nsImage = NSImage(cgImage: image, size: bounds.size)
        nsImage.draw(in: bounds)

        // 绘制所有标注及正在拉取的草稿
        var all = state.annotations
        if let draft = state.draft {
            all.append(draft)
        }
        for ann in all {
            AnnotationRenderer.drawSingleAnnotation(ann, in: ctx, size: bounds.size, baseImage: image, scale: 1.0)
        }
    }

    func renderCompositedImage() -> CGImage {
        AnnotationRenderer.renderAnnotations(state.annotations, onto: image)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview != nil ? convert(point, from: superview) : point

        // 右上角关闭区域（扩大至 44x44 超舒适命中区）：无论点到圆圈还是圆圈周围几像素，100% 命中关闭按钮
        let closeHitRect = closeButton.frame.insetBy(dx: -8, dy: -8)
        if closeHitRect.contains(localPoint) || (localPoint.x >= bounds.width - 44 && localPoint.y <= 44) {
            return closeButton
        }

        if let field = activeTextField {
            if field.frame.contains(localPoint) {
                return field
            }
        }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if state.activeKind != nil {
            addCursorRect(bounds, cursor: LensoCursor.crosshair)
        } else {
            addCursorRect(bounds, cursor: .arrow)
        }
        // 右上角关闭区域悬停显示手型指针
        let closeHoverRect = NSRect(x: bounds.width - 44, y: 0, width: 44, height: 44)
        addCursorRect(closeHoverRect, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        if activeTextField != nil {
            commitTextEditing()
        }

        let pt = convert(event.locationInWindow, from: nil)

        // 双重保障：只要在右上角 44x44 区域按下，瞬间彻底关闭
        if pt.x >= bounds.width - 44 && pt.y <= 44 {
            onClose?()
            return
        }

        // 选择 / 移动模式：双击或多次快速点击立即 100% 灵敏关闭
        if state.activeKind == nil {
            if event.clickCount >= 2 {
                onClose?()
                return
            }
            initialMouseScreenLocation = NSEvent.mouseLocation
            initialWindowOrigin = window?.frame.origin ?? .zero
            isDraggingWindow = true
            return
        }

        let norm = CGPoint(
            x: min(max(pt.x / max(1, bounds.width), 0), 1),
            y: min(max(pt.y / max(1, bounds.height), 0), 1)
        )

        // 文字标注工具：点击位置弹出输入框
        if state.activeKind == .text {
            startTextEditing(at: pt, norm: norm)
            return
        }

        // 其它标注工具：开始绘制
        state.draft = Annotation(
            kind: state.activeKind!,
            start: norm,
            end: norm,
            colorIndex: state.colorIndex,
            strokeWidth: state.strokeWidth
        )
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if state.activeKind == nil && isDraggingWindow {
            guard let window else { return }
            let currentMouse = NSEvent.mouseLocation
            let dx = currentMouse.x - initialMouseScreenLocation.x
            let dy = currentMouse.y - initialMouseScreenLocation.y
            window.setFrameOrigin(NSPoint(x: initialWindowOrigin.x + dx, y: initialWindowOrigin.y + dy))
            onWindowMovedOrResized?()
            return
        }

        guard var draft = state.draft else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let norm = CGPoint(
            x: min(max(pt.x / max(1, bounds.width), 0), 1),
            y: min(max(pt.y / max(1, bounds.height), 0), 1)
        )
        draft.end = norm
        state.draft = draft
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if state.activeKind == nil {
            isDraggingWindow = false
            onWindowMovedOrResized?()
            return
        }

        guard let draft = state.draft else { return }
        let dx = abs(draft.end.x - draft.start.x) * bounds.width
        let dy = abs(draft.end.y - draft.start.y) * bounds.height
        if dx > 4 || dy > 4 {
            state.push(draft)
        }
        state.draft = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if activeTextField != nil {
            cancelTextEditing()
            return
        }
        if state.draft != nil {
            state.draft = nil
            needsDisplay = true
            return
        }
        if state.activeKind != nil {
            state.activeKind = nil
            window?.invalidateCursorRects(for: self)
            return
        }
        // 选择模式下右键：呼出或关闭操作工具栏
        onToggleEditing?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            if activeTextField != nil {
                cancelTextEditing()
                return
            }
            if state.activeKind != nil {
                state.activeKind = nil
                window?.invalidateCursorRects(for: self)
                return
            }
            onToggleEditing?()
            return
        }
        if event.keyCode == 49 { // Space
            onToggleEditing?()
            return
        }
        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.05 else { return }

        let zoomFactor: CGFloat = delta > 0 ? 1.08 : 0.92
        let newScale = min(max(currentScale * zoomFactor, 0.2), 5.0)
        guard newScale != currentScale else { return }

        currentScale = newScale
        AppSettings.shared.previewScale = newScale
        guard let window else { return }

        let mouseScreen = NSEvent.mouseLocation
        let oldFrame = window.frame
        let newWidth = max(60, round(baseSize.width * newScale))
        let newHeight = max(40, round(baseSize.height * newScale))

        let relX = (mouseScreen.x - oldFrame.minX) / max(1, oldFrame.width)
        let relY = (mouseScreen.y - oldFrame.minY) / max(1, oldFrame.height)

        let newX = mouseScreen.x - newWidth * relX
        let newY = mouseScreen.y - newHeight * relY
        let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)

        window.setFrame(newFrame, display: true)
        onWindowMovedOrResized?()
    }

    override func magnify(with event: NSEvent) {
        let zoomFactor = 1.0 + event.magnification
        let newScale = min(max(currentScale * zoomFactor, 0.2), 5.0)
        guard newScale != currentScale else { return }

        currentScale = newScale
        AppSettings.shared.previewScale = newScale

        guard let window else { return }
        let mouseScreen = NSEvent.mouseLocation
        let oldFrame = window.frame
        let newWidth = max(60, round(baseSize.width * newScale))
        let newHeight = max(40, round(baseSize.height * newScale))

        let relX = (mouseScreen.x - oldFrame.minX) / max(1, oldFrame.width)
        let relY = (mouseScreen.y - oldFrame.minY) / max(1, oldFrame.height)

        let newX = mouseScreen.x - newWidth * relX
        let newY = mouseScreen.y - newHeight * relY
        window.setFrame(NSRect(x: newX, y: newY, width: newWidth, height: newHeight), display: true)
        onWindowMovedOrResized?()
    }

    private func startTextEditing(at point: NSPoint, norm: CGPoint) {
        activeTextField?.removeFromSuperview()
        let field = NSTextField(frame: NSRect(x: max(8, point.x), y: max(8, point.y), width: 180, height: 26))
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9)
        field.textColor = AnnotationPaletteNS[state.colorIndex]
        field.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        field.focusRingType = .none
        field.delegate = self
        field.placeholderString = "输入文本并回车"
        addSubview(field)
        window?.makeFirstResponder(field)
        self.activeTextField = field
        self.textStartNormPoint = norm
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEditing()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextEditing()
            return true
        }
        return false
    }

    private func commitTextEditing() {
        guard let field = activeTextField, let start = textStartNormPoint else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)])
            let endNorm = CGPoint(
                x: min(1, start.x + size.width / max(1, bounds.width)),
                y: min(1, start.y + size.height / max(1, bounds.height))
            )
            var ann = Annotation(
                kind: .text,
                start: start,
                end: endNorm,
                colorIndex: state.colorIndex,
                strokeWidth: state.strokeWidth
            )
            ann.text = text
            state.push(ann)
        }
        field.removeFromSuperview()
        activeTextField = nil
        textStartNormPoint = nil
        needsDisplay = true
    }

    private func cancelTextEditing() {
        activeTextField?.removeFromSuperview()
        activeTextField = nil
        textStartNormPoint = nil
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.alphaValue = 1.0
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.alphaValue = 0.85
    }
}
