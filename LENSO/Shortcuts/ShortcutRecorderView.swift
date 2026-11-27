import AppKit
import Observation
import SwiftUI

/// 快捷键录制控件：点击后进入录制状态，Esc 取消，Delete 恢复默认。
struct ShortcutRecorderView: View {
    let action: ShortcutAction
    let store: ShortcutStore

    @State private var model = ShortcutRecorderModel()
    @State private var hotKeyManager = GlobalHotKeyManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasSystemFailure: Bool {
        hotKeyManager.failedActions.contains(action)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
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
                                model.isRecording
                                    ? LensoColors.kleinBlueBright
                                    : (hasSystemFailure ? Color.orange.opacity(0.75) : Color.black.opacity(0.08)),
                                lineWidth: model.isRecording ? 1.5 : 1
                            )
                    }
                    .lensoAnimation(LensoAnimations.snappy, value: model.isRecording, reduceMotion: reduceMotion)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(LensoPressButtonStyle())
            .background {
                RecorderAnchorView { view in
                    model.anchorView = view
                }
            }
            .help("点击后按下新的快捷键；Esc 取消，Delete 恢复默认")

            if model.isRecording {
                Text("Esc 取消 · Delete 恢复默认")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            } else if let warning = model.warning {
                HStack(spacing: 6) {
                    Text(warning)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .lineLimit(1)

                    if let conflict = model.pendingConflict {
                        Button("替换冲突快捷键") {
                            store.replaceConflict(conflict.combo, for: action, replacing: conflict.other)
                            model.warning = nil
                            model.pendingConflict = nil
                        }
                        .buttonStyle(LensoPressButtonStyle())
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LensoColors.kleinBlueSoft))
                    }
                }
                .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            } else if hasSystemFailure {
                Text("可能被系统占用，建议更换")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
                    .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }
        }
        .lensoAnimation(LensoAnimations.snappy, value: model.isRecording, reduceMotion: reduceMotion)
        .lensoAnimation(LensoAnimations.snappy, value: model.warning, reduceMotion: reduceMotion)
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
                model.pendingConflict = nil
            }
        )
    }

    private func capture(_ combo: ShortcutCombo) {
        if let other = store.conflict(for: combo, excluding: action) {
            model.warning = "与「\(other.title)」冲突"
            model.pendingConflict = (combo, other)
            return
        }

        guard store.set(combo, for: action) else {
            model.warning = "请至少包含一个修饰键"
            model.pendingConflict = nil
            return
        }

        model.warning = nil
        model.pendingConflict = nil
    }
}

/// 保证同一时间只有一个快捷键录制器处于激活状态。
@MainActor
private final class ShortcutRecorderCoordinator {
    static let shared = ShortcutRecorderCoordinator()
    private weak var activeModel: ShortcutRecorderModel?

    private init() {}

    func activate(_ model: ShortcutRecorderModel) {
        if activeModel !== model {
            activeModel?.stop()
            activeModel = model
        }
    }

    func deactivate(_ model: ShortcutRecorderModel) {
        if activeModel === model {
            activeModel = nil
        }
    }
}

/// 管理本地键盘事件监听的生命周期。
@Observable
@MainActor
private final class ShortcutRecorderModel {
    var isRecording = false
    var warning: String?
    var pendingConflict: (combo: ShortcutCombo, other: ShortcutAction)?
    @ObservationIgnored weak var anchorView: NSView?

    @ObservationIgnored private nonisolated(unsafe) var keyMonitor: Any?
    @ObservationIgnored private nonisolated(unsafe) var mouseMonitor: Any?
    @ObservationIgnored private var onCapture: (@MainActor (ShortcutCombo) -> Void)?
    @ObservationIgnored private var onClear: (@MainActor () -> Void)?

    func start(
        onCapture: @escaping @MainActor (ShortcutCombo) -> Void,
        onClear: @escaping @MainActor () -> Void
    ) {
        guard !isRecording else { return }
        ShortcutRecorderCoordinator.shared.activate(self)

        self.onCapture = onCapture
        self.onClear = onClear
        warning = nil
        pendingConflict = nil
        isRecording = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            var result: NSEvent? = event
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                result = self.handle(event)
            }
            return result
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                if let anchor = self.anchorView, anchor.window === event.window {
                    let pt = anchor.convert(event.locationInWindow, from: nil)
                    if !anchor.bounds.contains(pt) {
                        self.stop()
                    }
                } else {
                    self.stop()
                }
            }
            return event
        }
    }

    func stop() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        keyMonitor = nil
        mouseMonitor = nil
        isRecording = false
        onCapture = nil
        onClear = nil
        ShortcutRecorderCoordinator.shared.deactivate(self)
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
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

/// 锚定快捷键按钮的真实 AppKit 视图坐标，确保点击外部判定在所有窗口布局下都精准无误。
private struct RecorderAnchorView: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView) }
    }
}
