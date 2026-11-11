import AppKit
import Observation
import SwiftUI

/// 快捷键录制控件：点击后进入录制状态，Esc 取消，Delete 恢复默认。
struct ShortcutRecorderView: View {
    let action: ShortcutAction
    let store: ShortcutStore

    @State private var model = ShortcutRecorderModel()

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button {
                toggleRecording()
            } label: {
                Text(model.isRecording ? "按下快捷键…" : store.combo(for: action).displayString)
                    .font(.system(size: 13, weight: model.isRecording ? .semibold : .medium))
                    .foregroundStyle(model.isRecording ? LensoColors.kleinBlueBright : Color.primary.opacity(0.75))
                    .frame(minWidth: 58)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(model.isRecording ? LensoColors.kleinBlueSoft : Color.white)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(
                                model.isRecording ? LensoColors.kleinBlueBright : Color.black.opacity(0.08),
                                lineWidth: 1
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("点击后按下新的快捷键；Esc 取消，Delete 恢复默认")

            if let warning = model.warning {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .onDisappear {
            model.stop()
        }
    }

    private func toggleRecording() {
        if model.isRecording {
            model.stop()
            return
        }

        model.start(
            onCapture: { combo in
                capture(combo)
            },
            onClear: {
                store.reset(action)
                model.warning = nil
            }
        )
    }

    private func capture(_ combo: ShortcutCombo) {
        if let other = store.conflict(for: combo, excluding: action) {
            model.warning = "与「\(other.title)」冲突"
            return
        }

        guard store.set(combo, for: action) else {
            model.warning = "请至少包含一个修饰键"
            return
        }

        model.warning = nil
    }
}

/// 管理本地键盘事件监听的生命周期。
@Observable
@MainActor
private final class ShortcutRecorderModel {
    var isRecording = false
    var warning: String?

    @ObservationIgnored private nonisolated(unsafe) var monitor: Any?
    @ObservationIgnored private var onCapture: (@MainActor (ShortcutCombo) -> Void)?
    @ObservationIgnored private var onClear: (@MainActor () -> Void)?

    func start(
        onCapture: @escaping @MainActor (ShortcutCombo) -> Void,
        onClear: @escaping @MainActor () -> Void
    ) {
        guard !isRecording else { return }

        self.onCapture = onCapture
        self.onClear = onClear
        warning = nil
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            var result: NSEvent? = event
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                result = self.handle(event)
            }
            return result
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        onCapture = nil
        onClear = nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// 返回 nil 表示吞掉事件（录制中），否则交回系统。
    private func handle(_ event: NSEvent) -> NSEvent? {
        // Esc 取消。
        if event.keyCode == 53 {
            stop()
            return nil
        }

        // Delete / Backspace 恢复默认。
        if event.keyCode == 51 || event.keyCode == 117 {
            let clear = onClear
            stop()
            clear?()
            return nil
        }

        guard let combo = ShortcutCombo(event: event) else {
            // 仅修饰键或无法识别的按键：保持录制状态。
            return nil
        }

        let capture = onCapture
        stop()
        capture?(combo)
        return nil
    }
}
