import AppKit
import SwiftUI

/// 右侧面板页签：标注 / OCR / 翻译
enum PanelTab { case annotation, ocr, translate }

/// OCR 运行阶段
enum OCRPhase { case idle, running, done, empty, failed }

/// 翻译运行阶段
enum TranslationPhase { case idle, running, done, failed }

// MARK: - 侧边栏工具组件

struct SideTool: View {
    let icon: String
    let label: String
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(active ? Color(nsColor: .controlAccentColor) : .primary.opacity(hovering ? 0.08 : 0.05))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(active ? .white : .primary)
            }
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onHover { hovering = $0 }
        .onTapGesture { action() }
    }
}

/// 形状快捷按钮（面板中排）
struct ShapeQuick: View {
    let icon: String
    let kind: AnnotationKind
    let state: AnnotationState
    let action: () -> Void

    @State private var hovering = false

    private var isActive: Bool { state.activeKind == kind }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isActive ? Color(nsColor: .controlAccentColor) : .primary.opacity(0.75))
            .frame(width: 30, height: 30)
            .onHover { hovering = $0 }
            .scaleEffect(hovering ? 1.1 : 1)
            .onTapGesture { action() }
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovering)
    }
}

/// 马赛克/高亮开关行
struct ToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    let onChange: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.75))
                .frame(width: 22)
            Text(label).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: isOn) { _ in onChange() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.04)))
    }
}

/// OCR 结果行：文字 + 置信度，点按复制这行
struct OCRLineRow: View {
    let line: RecognizedText
    let onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.text)
                .font(.system(size: 13))
                .lineLimit(nil)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Text("\(Int(line.confidence * 100))%")
                .font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
                .padding(.top, 2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture {
            onCopy()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        }
        .overlay(alignment: .trailing) {
            if copied {
                Text("已复制")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
                    .padding(.trailing, 6)
            }
        }
        .help("点按复制这行")
    }
}

/// 翻译结果行：原文（小灰）+ 译文，点按复制译文
struct TranslationLineRow: View {
    let original: String
    let translated: String
    let onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(original)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .textSelection(.enabled)
            if translated.isEmpty {
                Text("这行翻译失败").font(.system(size: 13)).foregroundStyle(.red)
            } else {
                Text(translated)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(nil)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture {
            onCopy()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        }
        .help("点按复制译文")
    }
}

/// 面板里的小按钮（OCR / 翻译页签用）
struct MiniButton: View {
    let label: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(disabled ? 0.03 : 0.07)))
                .foregroundStyle(disabled ? .tertiary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - 文字标注输入框（NSTextField 包装：回车/失焦提交，Esc 取消）

/// Esc 键不走默认行为，交给 onEscape 处理，避免触发编辑器整体的 Esc 取消。
final class CancelableTextField: NSTextField {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

struct AnnotationTextField: NSViewRepresentable {
    var color: NSColor
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = CancelableTextField()
        field.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        field.textColor = color
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = color.withAlphaComponent(0.12)
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.layer?.borderColor = color.withAlphaComponent(0.5).cgColor
        field.layer?.borderWidth = 1
        let coordinator = context.coordinator
        field.onEscape = { [weak coordinator] in
            guard let coordinator, !coordinator.finished else { return }
            coordinator.finished = true
            onCancel()
        }
        // 入场即聚焦，等一帧让窗口完成布局
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onCommit: (String) -> Void
        var finished = false

        init(onCommit: @escaping (String) -> Void) {
            self.onCommit = onCommit
        }

        /// 回车与失焦都会走到这里；Esc 已在 keyDown 拦截，不会重复提交。
        func controlTextDidEndEditing(_ obj: Notification) {
            guard !finished, let field = obj.object as? NSTextField else { return }
            finished = true
            onCommit(field.stringValue)
        }
    }
}
