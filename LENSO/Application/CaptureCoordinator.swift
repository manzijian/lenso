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

    let capture: ScreenCapturing
    let clipboard: ClipboardWriting
    let errorPresenter: ErrorPresenting
    let store: ScreenshotStore

    private var selector: RegionSelectorController?
    private var editorPanel: NSPanel?
    /// 进入编辑器前的前台应用，截图结束后把焦点还回去，避免 lenso 被顶到最前
    private var previousFrontApp: NSRunningApplication?
    private var editorHost: NSHostingView<CaptureEditorView>?
    /// 钉图控制器集合（持有引用防止释放）
    private var pinnedControllers: [PinnedScreenshotController] = []
    /// 热键触发瞬间的前台应用，作为本次截图的来源标识
    private(set) var lastSourceApp: String?

    init(
        capture: ScreenCapturing = ScreenCaptureService(),
        clipboard: ClipboardWriting = SystemClipboardWriter(),
        errorPresenter: ErrorPresenting = SystemErrorPresenter(),
        store: ScreenshotStore = .shared
    ) {
        self.capture = capture
        self.clipboard = clipboard
        self.errorPresenter = errorPresenter
        self.store = store
        super.init()
    }

    func startRegionCapture() {
        log.info("startRegionCapture triggered")
        // 在遮罩上屏之前记录当前前台应用，作为本次截图的来源
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastSourceApp = front.localizedName
        } else {
            lastSourceApp = nil
        }
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
        // 权限前置拦截：若无屏幕录制权限，直接拦截并触发系统权限申请，绝不上屏选区遮罩或让用户无效框选
        var hasAccess = CGPreflightScreenCaptureAccess()
        if !hasAccess {
            hasAccess = await CapturePermissionService.probeAccess()
        }
        guard hasAccess else {
            log.warning("startRegionCapture blocked: screen recording permission not granted")
            NSSound.beep()
            _ = CGRequestScreenCaptureAccess()
            return
        }

        // 丝滑 v2：面板立刻上屏（不预抓图），选区里透出实时桌面。
        // 确认后才抓一张全屏当编辑器背景，抓时把选区面板排除在外。
        let selector = RegionSelectorController()
        self.selector = selector
        selector.begin { [weak self, weak selector] rect, displayID, panelWindowNumber, prefrozen in
            Task { @MainActor in
                guard let self, let selector, !selector.isDismissed else { return }
                // 核心修复：选区确认后立刻关闭选区全屏面板，彻底退出截图遮罩状态，
                // 绝不拖到后续抓图或报错弹窗之后，杜绝“弹出错误时还在截图状态”
                selector.dismiss()
                self.selector = nil

                _ = await self.captureFrameAndProceed(
                    displayID: displayID,
                    excludedWindowIDs: [panelWindowNumber],
                    prefrozen: prefrozen,
                    rect: rect
                )
            }
        }
    }

    @discardableResult
    func captureFrameAndProceed(
        displayID: CGDirectDisplayID,
        excludedWindowIDs: [CGWindowID],
        prefrozen: CGImage?,
        rect: CGRect
    ) async -> Bool {
        do {
            // 优先用选区阶段就已经冻结好的画面：编辑器可以立刻上屏。
            // 只有冻结帧还没到位（热键按下后不到 ~200ms 就确认）才现场抓。
            let frozen: CGImage
            if let prefrozen {
                frozen = prefrozen
            } else {
                frozen = try await capture.captureDisplayExcluding(
                    displayID: displayID, excludedWindowIDs: excludedWindowIDs
                )
            }
            let screenFrame = NSScreen.screens
                .first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
                        || ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
                })?
                .frame ?? rect
            showFullEditor(frozen: frozen, screenFrame: screenFrame, initialSelection: rect)
            return true
        } catch {
            NSSound.beep()
            log.error("capture failed: \(error.localizedDescription, privacy: .public)")
            if Self.isPermissionError(error) {
                errorPresenter.presentCaptureError(
                    title: "无法截图：缺少屏幕录制权限",
                    message: "请到「系统设置 → 隐私与安全性 → 屏幕录制」中为 lenso 开启权限，然后重新截图。",
                    isPermission: true
                )
            } else {
                errorPresenter.presentCaptureError(title: "截图失败", message: error.localizedDescription, isPermission: false)
            }
            return false
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
            // 这里刻意不用 .nonactivatingPanel：非激活面板拿不到输入法上下文，
            // 中文候选框挂不上来。编辑器需要文字标注，所以必须是普通可激活面板。
            styleMask: [.borderless],
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
        // 选区阶段刻意不激活 App（否则会把自己的窗口顶到最前，盖住要截的应用）。
        // 但编辑器需要接管键盘、输入法和标注，所以进编辑器时再激活；
        // 这时画面已经冻结，激活不会影响截取内容。
        // 记录截图前的前台应用，结束时把焦点还回去
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousFrontApp = front
        }
        NSApp.activate(ignoringOtherApps: true)
        LensoWindowMotion.present(panel, duration: 0.16, makeKey: true)
        // 激活是异步协作的：等一拍再确认一次 key 状态，
        // 否则面板可能没拿到键盘焦点，文字标注就完全打不进字。
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKey()
        }
        editorPanel = panel
        log.info("full editor shown on display \(NSStringFromRect(panel.screen?.frame ?? .zero), privacy: .public)")
    }

    func closeEditor() {
        if let panel = editorPanel {
            editorPanel = nil
            editorHost = nil
            LensoWindowMotion.dismiss(panel, duration: 0.12) {
                panel.close()
            }
        } else {
            editorHost = nil
        }
        // 把焦点还给截图前的那个应用，lenso 不留在最前面
        if let app = previousFrontApp, !app.isTerminated {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        previousFrontApp = nil
    }

    func handleFinish(finalImage: CGImage?) {
        guard let image = finalImage else {
            log.info("editor discarded")
            return
        }
        do {
            let record = try store.save(image: image, capturedAt: Date(), sourceApp: lastSourceApp)
            // 截图确定之后：默认 100% 自动复制到剪贴板，支持所有现代 App 直接 ⌘V 粘贴
            copyToClipboard(image: image)
            NotificationCenter.default.post(name: .screenshotSaved, object: record)
            if AppSettings.shared.showFloatingPreview {
                SaveToastController.shared.show(
                    title: "已复制到剪贴板",
                    subtitle: "已自动保存到图库",
                    thumbnail: try? store.loadThumbnail(record)
                )
            }
            if AppSettings.shared.showPreviewAfterCapture {
                NotificationCenter.default.post(name: .openPreviewForScreenshot, object: record.id)
            }
            log.info("saved \(record.filename, privacy: .public)")
        } catch {
            // 即使保存到磁盘出现异常，剪贴板也 100% 确保复制成功
            copyToClipboard(image: image)
            SaveToastController.shared.show(
                title: "已复制到剪贴板",
                subtitle: "未保存到磁盘",
                thumbnail: image,
                isError: true
            )
            NSSound.beep()
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var previewController: PinnedScreenshotController?
    private var keyMonitor: Any?

    private func currentTopPinnedController() -> PinnedScreenshotController? {
        previewController ?? pinnedControllers.last
    }

    private func setupKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc 键快速一键关闭当前浮动预览或贴图
                // 若正在编辑或有文字输入框，交给 PinnedImageView.keyDown 逐级退出
                if let top = self.currentTopPinnedController(), top.isCurrentlyEditing {
                    return event
                }
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

    /// SCK 在没有屏幕录制权限或用户拒绝 TCC 时抛的错误
    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        let desc = error.localizedDescription
        if desc.localizedCaseInsensitiveContains("tcc")
            || desc.contains("权限")
            || desc.contains("拒绝")
            || desc.localizedCaseInsensitiveContains("declined")
            || desc.localizedCaseInsensitiveContains("denied")
            || desc.localizedCaseInsensitiveContains("not permitted") {
            return true
        }
        if ns.domain.contains("ScreenCaptureKit") || ns.domain.contains("SCStreamErrorDomain") {
            return true
        }
        return ns.code == -3801 || ns.code == -3802 || ns.code == 1
    }

    func copyToClipboard(image: CGImage) {
        clipboard.writeImage(image)
    }
}



