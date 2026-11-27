import AppKit
import CoreGraphics
import SwiftUI

// MARK: - 贴图控制器与独立浮动工具栏（专属针对贴图操作，不遮挡屏幕也不进入二次截图）

@MainActor
final class PinnedScreenshotController: NSObject {
    weak var coordinator: CaptureCoordinator?
    let panel: NSPanel
    let toolbarPanel: NSPanel
    let sidePanel: NSPanel
    let imageView: PinnedImageView
    let state = AnnotationState()
    let pinnedState = PinnedEditorState()
    private var isToolbarVisible = false

    var isCurrentlyEditing: Bool {
        isToolbarVisible || state.activeKind != nil || pinnedState.isSidePanelVisible || imageView.hasActiveTextField
    }

    init(image: CGImage, initialFrame: NSRect?, coordinator: CaptureCoordinator) {
        self.coordinator = coordinator

        let size: NSSize
        let origin: NSPoint

        if let initialFrame {
            size = initialFrame.size
            origin = initialFrame.origin
        } else {
            let screen = NSScreen.main
            let backingScale = screen?.backingScaleFactor ?? 2.0
            var w = CGFloat(image.width) / backingScale
            var h = CGFloat(image.height) / backingScale

            // 1. 确保小图具有舒适清晰的最小预览尺寸（避免只有几十像素导致太小找不到）
            let minComfortableWidth: CGFloat = 460
            let minComfortableHeight: CGFloat = 300
            let aspect = w / max(1, h)
            if w < minComfortableWidth && h < minComfortableHeight {
                if aspect >= 1 {
                    w = minComfortableWidth
                    h = round(w / aspect)
                } else {
                    h = minComfortableHeight
                    w = round(h * aspect)
                }
            }

            // 2. 应用用户放大/记忆的缩放比例（放大过某张照片后，再次打开或其他照片都自动保持那么大）
            let userScale = max(0.4, min(AppSettings.shared.previewScale, 4.0))
            w = round(w * userScale)
            h = round(h * userScale)

            // 3. 限制在屏幕可视区的 88% 以内，防止超出显示器屏幕
            let maxW = (screen?.visibleFrame.width ?? 1200) * 0.88
            let maxH = (screen?.visibleFrame.height ?? 800) * 0.88
            let fitScale = min(1.0, min(maxW / max(1, w), maxH / max(1, h)))
            w = round(w * fitScale)
            h = round(h * fitScale)
            size = NSSize(width: max(160, w), height: max(100, h))

            if let screen {
                origin = NSPoint(
                    x: screen.visibleFrame.midX - size.width / 2,
                    y: screen.visibleFrame.midY - size.height / 2
                )
            } else {
                origin = .zero
            }
        }

        // 1. 主贴图浮窗
        let pinnedPanel = PinnedPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        pinnedPanel.level = .floating
        pinnedPanel.isOpaque = false
        pinnedPanel.backgroundColor = .clear
        pinnedPanel.hasShadow = true
        pinnedPanel.isMovableByWindowBackground = false
        pinnedPanel.hidesOnDeactivate = false
        panel = pinnedPanel

        // 2. 底部工具栏卫星浮窗
        toolbarPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 510, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toolbarPanel.level = .floating
        toolbarPanel.isOpaque = false
        toolbarPanel.backgroundColor = .clear
        toolbarPanel.hasShadow = false
        toolbarPanel.hidesOnDeactivate = false

        // 3. 右侧属性/OCR/翻译卡片卫星浮窗
        sidePanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        sidePanel.level = .floating
        sidePanel.isOpaque = false
        sidePanel.backgroundColor = .clear
        sidePanel.hasShadow = false
        sidePanel.hidesOnDeactivate = false

        imageView = PinnedImageView(frame: NSRect(origin: .zero, size: size), image: image, state: state)
        super.init()

        imageView.onClose = { [weak self] in
            self?.close()
        }
        imageView.onToggleEditing = { [weak self] in
            self?.toggleToolbar()
        }
        imageView.onCopy = { [weak self] in
            self?.copyImage()
        }
        imageView.onSave = { [weak self] in
            self?.saveImage()
        }
        imageView.onWindowMovedOrResized = { [weak self] in
            self?.updatePositions()
        }

        (panel as? PinnedPanel)?.onCancel = { [weak self] in
            _ = self?.imageView.stepBackOnEscape()
        }
        (panel as? PinnedPanel)?.onSpace = { [weak self] in
            self?.toggleToolbar()
        }
        (panel as? PinnedPanel)?.onKeyCommand = { [weak self] event in
            self?.imageView.handleKeyEvent(event) ?? false
        }

        panel.contentView = imageView
        panel.setFrameOrigin(origin)
        LensoWindowMotion.present(panel, duration: 0.14, makeKey: true)
        panel.makeFirstResponder(imageView)

        // 配置工具栏视图
        let toolbarView = PinnedToolbarView(
            state: state,
            pinnedState: pinnedState,
            onUndo: { [weak self] in
                self?.state.undo()
                self?.imageView.needsDisplay = true
            },
            onRedo: { [weak self] in
                self?.state.redo()
                self?.imageView.needsDisplay = true
            },
            onToggleAnnotation: { [weak self] in
                self?.toggleTab(.annotation)
            },
            onToggleTranslate: { [weak self] in
                self?.toggleTab(.translate)
            },
            onToggleOCR: { [weak self] in
                self?.toggleTab(.ocr)
            },
            onCopy: { [weak self] in
                self?.copyImage()
            },
            onSave: { [weak self] in
                self?.saveImage()
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
        let toolbarHosting = NSHostingView(rootView: toolbarView)
        toolbarHosting.appearance = NSAppearance(named: .aqua)
        toolbarPanel.contentView = toolbarHosting

        // 配置右侧属性/OCR/翻译面板视图
        let sideView = PinnedSidePanelView(
            state: state,
            pinnedState: pinnedState,
            onRunOCR: { [weak self] in self?.runOCR() },
            onCopyAllOCR: { [weak self] in
                guard let self else { return }
                let text = self.pinnedState.ocrLines.map(\.text).joined(separator: "\n")
                self.copyText(text)
            },
            onSaveOCRToNotes: { [weak self] in self?.saveOCRToNotes() },
            onCopyText: { [weak self] text in self?.copyText(text) },
            onRunTranslation: { [weak self] in self?.runTranslation() },
            onCopyAllTranslations: { [weak self] in
                guard let self else { return }
                let text = self.pinnedState.ocrLines.map { self.pinnedState.translations[$0.id] ?? "" }.joined(separator: "\n")
                self.copyText(text)
            },
            onQuickCopy: { [weak self] in self?.copyImage() },
            onClose: { [weak self] in self?.hideSidePanel() }
        )
        let sideHosting = NSHostingView(rootView: sideView)
        sideHosting.appearance = NSAppearance(named: .aqua)
        sidePanel.contentView = sideHosting
    }

    func toggleToolbar() {
        if isToolbarVisible {
            hideAll()
        } else {
            showAll()
        }
    }

    func showAll() {
        guard !isToolbarVisible else { return }
        isToolbarVisible = true
        imageView.isEditing = true

        updatePositions()

        if toolbarPanel.parent != panel {
            panel.addChildWindow(toolbarPanel, ordered: .above)
        }
        LensoWindowMotion.present(toolbarPanel, duration: 0.16, slideY: 6)

        if pinnedState.isSidePanelVisible {
            if sidePanel.parent != panel {
                panel.addChildWindow(sidePanel, ordered: .above)
            }
            LensoWindowMotion.present(sidePanel, duration: 0.16, slideY: 6)
        }
    }

    func hideAll() {
        guard isToolbarVisible else { return }
        isToolbarVisible = false
        imageView.isEditing = false
        pinnedState.isSidePanelVisible = false
        state.activeKind = nil

        LensoWindowMotion.dismiss(toolbarPanel, duration: 0.12, slideY: 6) { [weak self] in
            guard let self, !self.isToolbarVisible else { return }
            self.panel.removeChildWindow(self.toolbarPanel)
        }

        if sidePanel.isVisible {
            LensoWindowMotion.dismiss(sidePanel, duration: 0.12, slideY: 6) { [weak self] in
                guard let self, !self.pinnedState.isSidePanelVisible else { return }
                self.panel.removeChildWindow(self.sidePanel)
            }
        }

        panel.invalidateCursorRects(for: imageView)
        imageView.needsDisplay = true
    }

    func toggleTab(_ tab: PanelTab) {
        if pinnedState.isSidePanelVisible && pinnedState.panelTab == tab {
            hideSidePanel()
        } else {
            showSidePanel(tab: tab)
        }
    }

    func showSidePanel(tab: PanelTab) {
        let wasVisible = pinnedState.isSidePanelVisible
        pinnedState.panelTab = tab
        pinnedState.isSidePanelVisible = true
        updateSidePanelPosition()
        if sidePanel.parent != panel {
            panel.addChildWindow(sidePanel, ordered: .above)
        }
        if !wasVisible || !sidePanel.isVisible {
            LensoWindowMotion.present(sidePanel, duration: 0.16, slideY: 6)
        } else {
            sidePanel.orderFront(nil)
        }

        if tab == .ocr && pinnedState.ocrPhase == .idle {
            runOCR()
        } else if tab == .translate && (pinnedState.translationPhase == .idle || pinnedState.translationPhase == .failed) {
            runTranslation()
        }
    }

    func hideSidePanel() {
        pinnedState.isSidePanelVisible = false
        LensoWindowMotion.dismiss(sidePanel, duration: 0.12, slideY: 6) { [weak self] in
            guard let self, !self.pinnedState.isSidePanelVisible else { return }
            self.panel.removeChildWindow(self.sidePanel)
        }
    }

    func updatePositions() {
        updateToolbarPosition()
        updateSidePanelPosition()
    }

    func updateToolbarPosition() {
        guard isToolbarVisible else { return }
        let pFrame = panel.frame
        let barWidth: CGFloat = 510
        let barHeight: CGFloat = 46
        let spacing: CGFloat = 8

        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 2560, height: 1440)

        var x = pFrame.midX - barWidth / 2
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - barWidth - 8))

        var y = pFrame.minY - barHeight - spacing
        if y < visibleFrame.minY + 8 {
            y = pFrame.maxY + spacing
        }

        toolbarPanel.setFrame(NSRect(x: x, y: y, width: barWidth, height: barHeight), display: true)
    }

    func updateSidePanelPosition() {
        guard pinnedState.isSidePanelVisible else { return }
        let pFrame = panel.frame
        let sideWidth: CGFloat = 340
        let sideHeight: CGFloat = 420
        let spacing: CGFloat = 12

        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 2560, height: 1440)

        // 优先放在贴图右侧；若右侧超屏则放左侧
        var x = pFrame.maxX + spacing
        if x + sideWidth > visibleFrame.maxX - 8 {
            x = pFrame.minX - sideWidth - spacing
        }
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - sideWidth - 8))

        var y = pFrame.maxY - sideHeight
        y = max(visibleFrame.minY + 8, min(y, visibleFrame.maxY - sideHeight - 8))

        sidePanel.setFrame(NSRect(x: x, y: y, width: sideWidth, height: sideHeight), display: true)
    }

    func close() {
        pinnedState.ocrTask?.cancel()
        pinnedState.translationTask?.cancel()
        hideAll()
        toolbarPanel.close()
        sidePanel.close()
        panel.orderOut(nil)
        panel.close()
        coordinator?.removePinnedController(self)
    }

    func copyImage() {
        let composited = imageView.renderCompositedImage()
        coordinator?.copyToClipboard(image: composited)
        if AppSettings.shared.showFloatingPreview {
            SaveToastController.shared.show(
                title: "已复制到剪贴板",
                subtitle: state.annotations.isEmpty ? "贴图原始图像" : "包含 \(state.annotations.count) 处标注",
                thumbnail: composited
            )
        }
    }

    func saveImage() {
        let composited = imageView.renderCompositedImage()
        do {
            let record = try ScreenshotStore.shared.save(
                image: composited,
                capturedAt: Date(),
                sourceApp: coordinator?.lastSourceApp
            )
            if AppSettings.shared.autoCopyAfterCapture {
                coordinator?.copyToClipboard(image: composited)
            }
            NotificationCenter.default.post(name: .screenshotSaved, object: record)
            if AppSettings.shared.showFloatingPreview {
                SaveToastController.shared.show(thumbnail: try? ScreenshotStore.shared.loadThumbnail(record))
            }
        } catch {
            NSSound.beep()
            SaveToastController.shared.show(
                title: "保存失败",
                subtitle: error.localizedDescription,
                thumbnail: nil,
                isError: true
            )
        }
    }
}
