import SwiftUI

/// 保存/操作反馈 Toast — 右下角浮现：「✓ 截图已保存 到图片库」+ 缩略图
@MainActor
final class SaveToastController {
    static let shared = SaveToastController()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(
        title: String = "截图已保存",
        subtitle: String = "到图片库",
        thumbnail: CGImage?,
        isError: Bool = false
    ) {
        // 错误提示始终展示，普通成功提示遵循用户设置
        if !isError {
            guard AppSettings.shared.showFloatingPreview else { return }
        }

        hideTask?.cancel()
        panel?.orderOut(nil)
        panel?.close()

        let toastView = SaveToastView(title: title, subtitle: subtitle, thumbnail: thumbnail, isError: isError)
        let hosting = NSHostingView(rootView: toastView)
        hosting.appearance = NSAppearance(named: .aqua)
        // 固定尺寸：fittingSize 在首次布局前可能为 0，导致窗口不可见
        let size = NSSize(width: 300, height: 64)
        hosting.frame = NSRect(origin: .zero, size: size)

        // 右下角：优先鼠标所在屏幕，退化为主屏
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { return }
        let frame = CGRect(
            x: screen.visibleFrame.maxX - size.width - 24,
            y: screen.visibleFrame.minY + 24,
            width: size.width,
            height: size.height
        )
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        self.panel = panel

        // 丝滑上浮入场（尊重系统减少动态效果）
        LensoWindowMotion.present(panel, duration: 0.24, slideY: 10, makeKey: false)

        hideTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(isError ? 3.2 : 2.4))
            guard !Task.isCancelled, let panel else { return }
            LensoWindowMotion.dismiss(panel, duration: 0.18, slideY: 6) { [weak self, weak panel] in
                panel?.close()
                if self?.panel === panel {
                    self?.panel = nil
                }
            }
        }
    }
}

struct SaveToastView: View {
    var title: String = "截图已保存"
    var subtitle: String = "到图片库"
    let thumbnail: CGImage?
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(isError ? Color.orange : Color.green)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let thumbnail {
                Image(decorative: thumbnail, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
                    )
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            // 透明宿主窗口里玻璃会“隐形”，用实体浅色底保证可见
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.98, green: 0.985, blue: 1.0).opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isError ? Color.orange.opacity(0.35) : Color.black.opacity(0.08), lineWidth: 1)
                )
        }
    }
}
