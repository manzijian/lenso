import SwiftUI

/// 保存成功 Toast — 右下角浮现：「✓ 截图已保存 到图片库」+ 缩略图
@MainActor
final class SaveToastController {
    static let shared = SaveToastController()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(title: String = "截图已保存", subtitle: String = "到图片库", thumbnail: CGImage?) {
        // 用户在设置中关闭浮动提示时，直接拦截不显示
        guard AppSettings.shared.showFloatingPreview else { return }

        hideTask?.cancel()
        panel?.orderOut(nil)
        panel?.close()

        let toastView = SaveToastView(title: title, subtitle: subtitle, thumbnail: thumbnail)
        let hosting = NSHostingView(rootView: toastView)
        hosting.appearance = NSAppearance(named: .aqua)
        // 固定尺寸：fittingSize 在首次布局前可能为 0，导致窗口不可见
        let size = NSSize(width: 300, height: 64)
        hosting.frame = NSRect(origin: .zero, size: size)

        // 右下角：主屏右下角向内 24pt
        guard let screen = NSScreen.main else { return }
        let frame = CGRect(
            x: screen.frame.maxX - size.width - 24,
            y: screen.frame.minY + 24,
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
        panel.orderFrontRegardless()
        self.panel = panel

        // 入场动画
        hosting.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hosting.animator().alphaValue = 1
        }

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    self?.panel?.contentView?.animator().alphaValue = 0
                }, completionHandler: {
                    self?.panel?.orderOut(nil)
                    self?.panel?.close()
                    self?.panel = nil
                })
            }
        }
    }
}

struct SaveToastView: View {
    var title: String = "截图已保存"
    var subtitle: String = "到图片库"
    let thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let thumbnail {
                Image(decorative: thumbnail, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
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
                        .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}
