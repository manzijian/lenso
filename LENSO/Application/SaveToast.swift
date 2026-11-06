import SwiftUI

/// 保存成功 Toast — 右下角浮现：「✓ 截图已保存 到图片库」+ 缩略图
@MainActor
final class SaveToastController {
    static let shared = SaveToastController()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(thumbnail: CGImage?) {
        hideTask?.cancel()
        panel?.orderOut(nil)
        panel?.close()

        let toastView = SaveToastView(thumbnail: thumbnail)
        let hosting = NSHostingView(rootView: toastView)
        let size = hosting.fittingSize

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
        panel.hasShadow = false
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        // 入场动画
        hosting.alphaValue = 0
        hosting.layer?.transform = CATransform3DMakeTranslation(0, -12, 0)
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
    let thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("截图已保存").font(.system(size: 13, weight: .semibold))
                Text("到图片库").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let thumbnail {
                Image(decorative: thumbnail, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
