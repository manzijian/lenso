import AppKit
import CoreGraphics
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.lenso.app", category: "capture")

/// 截图流程编排（规范 6.1）：
/// 权限 → 选区 → 抓帧 → 编辑覆盖层（保存/复制/置顶/OCR/丢弃）→ 按动作落盘
@MainActor
final class CaptureCoordinator: NSObject {
    static let shared = CaptureCoordinator()

    private let capture = ScreenCaptureService()
    private var selector: RegionSelectorController?
    private var editorPanel: NSPanel?
    private var editorHost: NSHostingView<CaptureEditorView>?
    /// 钉图控制器集合（持有引用防止释放）
    private var pinnedControllers: [PinnedScreenshotController] = []

    func startRegionCapture() {
        log.info("startRegionCapture triggered")
        // 已经有一轮选区在进行：先把它收掉再重开，而不是默默不理
        // （用户按了热键却什么都没发生，会以为应用卡住了）
        if let selector {
            log.info("selector already open, restarting")
            selector.cancel()
            self.selector = nil
        }
        Task { await startRegionCaptureAsync() }
    }

    private func startRegionCaptureAsync() async {
        // 触发阶段**不再**做权限探测。
        //
        // 以前这里会先枚举 SCShareableContent 当作权限检查，问题有两个：
        //   1. 枚举本身会偶发失败（锁屏、显示器热插拔、系统繁忙都会），
        //      一失败就直接 return，用户看到的就是「按了热键没反应」；
        //   2. 选区浮层根本不需要屏幕录制权限——它只是个透明面板。
        // 所以现在先无条件把选区上屏，真正抓图时若没权限，在「确认」那一步
        // 给出明确提示（见下面的 catch）。触发因此永远是即时的。

        // 丝滑 v2：面板立刻上屏（不预抓图），选区里透出实时桌面。
        // 确认后才抓一张全屏当编辑器背景，抓时把选区面板排除在外。
        let selector = RegionSelectorController()
        self.selector = selector
        let captureService = capture
        selector.begin { [weak self, weak selector] rect, displayID, panelWindowNumber, prefrozen in
            Task { @MainActor in
                guard let self, let selector, !selector.isDismissed else { return }
                do {
                    // 优先用选区阶段就已经冻结好的画面：编辑器可以立刻上屏。
                    // 只有冻结帧还没到位（热键按下后不到 ~200ms 就确认）才现场抓。
                    let frozen: CGImage
                    if let prefrozen {
                        frozen = prefrozen
                    } else {
                        frozen = try await captureService.captureDisplayExcluding(
                            displayID: displayID, excludedWindowIDs: [panelWindowNumber]
                        )
                    }
                    let screenFrame = NSScreen.screens
                        .first(where: {
                            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
                                || ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
                        })?
                        .frame ?? rect
                    self.showFullEditor(frozen: frozen, screenFrame: screenFrame, initialSelection: rect)
                    selector.dismiss()
                    self.selector = nil
                } catch {
                    NSSound.beep()
                    log.error("capture failed: \(error.localizedDescription, privacy: .public)")
                    if Self.isPermissionError(error) {
                        self.presentCaptureError(
                            title: "无法截图：缺少屏幕录制权限",
                            message: "请到「系统设置 → 隐私与安全性 → 屏幕录制」中为 lenso 开启权限，然后重新截图。",
                            isPermission: true
                        )
                    } else {
                        self.presentCaptureError(title: "截图失败", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func showFullEditor(
        frozen: CGImage,
        screenFrame: CGRect,
        initialSelection: CGRect
    ) {
        let coordinator = self
        let editorView = CaptureEditorView(
            frozenImage: frozen,
            screenFrame: screenFrame,
            initialSelection: initialSelection,
            onComplete: { [weak coordinator] finalImage in
                coordinator?.closeEditor()
                coordinator?.handleFinish(finalImage: finalImage)
            },
            onQuickCopy: { [weak coordinator] image in
                coordinator?.copyToClipboard(image: image)
                // 只复制不保存：提示必须是“已复制到剪贴板”，不许写“截图已保存”
                if AppSettings.shared.showFloatingPreview {
                    SaveToastController.shared.show(
                        title: "已复制到剪贴板", subtitle: "未保存到图库", thumbnail: image
                    )
                }
            },
            onPin: { [weak coordinator] image, rect in
                coordinator?.closeEditor()
                coordinator?.pin(image: image, initialFrame: rect)
            }
        )
        let hosting = NSHostingView(rootView: editorView)
        hosting.appearance = NSAppearance(named: .aqua) // 编辑器浅色玻璃
        editorHost = hosting

        let panel = EditorPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hosting
        panel.setFrame(screenFrame, display: true)
        panel.onCancel = { [weak self] in
            self?.closeEditor()
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        editorPanel = panel
        log.info("full editor shown on display \(NSStringFromRect(panel.screen?.frame ?? .zero), privacy: .public)")
    }

    private func closeEditor() {
        editorPanel?.orderOut(nil)
        editorPanel?.close()
        editorPanel = nil
        editorHost = nil
    }

    private func handleFinish(finalImage: CGImage?) {
        guard let image = finalImage else {
            log.info("editor discarded")
            return
        }
        do {
            let record = try ScreenshotStore.shared.save(image: image, capturedAt: Date())
            // 截图确定之后：默认 100% 自动复制到剪贴板，支持所有现代 App 直接 ⌘V 粘贴
            copyToClipboard(image: image)
            // 记录到剪贴板历史，使唤出搜索时能立即在最顶部看到并滚到
            _ = try? ScreenshotStore.shared.saveClipboardImage(image, sourceApp: "截图")
            NotificationCenter.default.post(name: .screenshotSaved, object: record)
            if AppSettings.shared.showFloatingPreview {
                SaveToastController.shared.show(
                    title: "已复制到剪贴板",
                    subtitle: "已自动保存到图库",
                    thumbnail: try? ScreenshotStore.shared.loadThumbnail(record)
                )
            }
            if AppSettings.shared.showPreviewAfterCapture {
                NotificationCenter.default.post(name: .openPreviewForScreenshot, object: record.id)
            }
            NSSound.beep()
            log.info("saved \(record.filename, privacy: .public)")
        } catch {
            // 即使保存到磁盘出现异常，剪贴板也 100% 确保复制成功
            copyToClipboard(image: image)
            _ = try? ScreenshotStore.shared.saveClipboardImage(image, sourceApp: "截图")
            if AppSettings.shared.showFloatingPreview {
                SaveToastController.shared.show(
                    title: "已复制到剪贴板",
                    subtitle: "未保存到磁盘",
                    thumbnail: image
                )
            }
            NSSound.beep()
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var previewController: PinnedScreenshotController?
    private var keyMonitor: Any?

    private func setupKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc 键快速一键关闭当前浮动预览或贴图
                if self.closeLatestPinnedOrPreview() {
                    return nil
                }
            }
            return event
        }
    }

    @discardableResult
    func closeLatestPinnedOrPreview() -> Bool {
        if let preview = previewController {
            preview.close()
            return true
        }
        if let last = pinnedControllers.last {
            last.close()
            return true
        }
        return false
    }

    /// 钉图 / 浮动预览：浮在所有窗口之上的纯粹可拖动图片窗（无任何包裹窗体与黑边，回到刚截图的原汁原味）
    func pin(image: CGImage, initialFrame: NSRect? = nil, isPreview: Bool = false) {
        setupKeyMonitorIfNeeded()
        // 如果是图库预览，先彻底关闭已有的旧预览浮窗，杜绝连续双击产生多重相同窗口堆叠、导致“关闭一次关不掉”的问题
        if isPreview {
            if let existing = previewController {
                existing.close()
                previewController = nil
            }
        }
        let controller = PinnedScreenshotController(image: image, initialFrame: initialFrame, coordinator: self)
        if isPreview {
            previewController = controller
        }
        pinnedControllers.append(controller)
        log.info("pinned screenshot controller created, total active: \(self.pinnedControllers.count)")
    }

    func removePinnedController(_ controller: PinnedScreenshotController) {
        pinnedControllers.removeAll { $0 === controller }
        if previewController === controller {
            previewController = nil
        }
    }

    /// SCK 在没有屏幕录制权限时抛的错误（域 SCStreamErrorDomain / 用户取消）。
    private static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "SCStreamErrorDomain" { return true }
        // CGError 里 .notPermitted / .invalidDisplay 也常被包成这个
        return ns.code == -3801 || ns.code == -3802
    }

    /// 截图失败时给一个用户看得见的提示（beep 太容易错过）。
    /// 用 NSAlert 而不是自绘浮层：失败路径要尽量简单，别再依赖别的东西能跑起来。
    private func presentCaptureError(title: String, message: String, isPermission: Bool = false) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        if isPermission {
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "好")
        } else {
            alert.addButton(withTitle: "好")
        }
        let response = alert.runModal()
        if isPermission && response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func copyToClipboard(image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        // 1. TIFF 基础数据
        if let tiff = nsImage.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)

            // 2. PNG 格式数据（关键：微信、飞书、现代浏览器与设计工具优先读取 PNG）
            if let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                pasteboard.setData(pngData, forType: .png)
            }
        }

        // 3. 原生图像对象写入（支持系统级粘贴）
        pasteboard.writeObjects([nsImage])
    }
}



