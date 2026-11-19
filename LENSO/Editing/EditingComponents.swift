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

// MARK: - 文字标注输入框（SwiftUI TextField + FocusState）

/// 之前这里包的是 NSTextField，NSHostingView 会在下一帧把第一响应者抢回去，
/// 输入框刚出现就失焦并被空提交，看起来就是「根本没有输入的地方」。
/// 现在改用 SwiftUI 原生 TextField + FocusState，焦点由 SwiftUI 自己管，稳定得多。
struct AnnotationTextField: View {
    @Binding var text: String
    var color: Color
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    @State private var finished = false
    @FocusState private var focused: Bool

    /// 输入框宽度跟着内容走（和最终画上去的文字同宽，不会出现被截断的窄框）
    private var measuredWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return max(96, ceil(width) + 10)
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .frame(width: measuredWidth, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                        color.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .focused($focused)
            .onSubmit { commit() }
            .onExitCommand { cancel() }
            .onAppear {
                // 等视图挂进窗口后再拿焦点，避免首个按键丢失
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    focused = true
                }
            }
            .onChange(of: focused) { _, isFocused in
                // 点到别处 = 确认这条文字
                if !isFocused { commit() }
            }
    }

    private func commit() {
        guard !finished else { return }
        finished = true
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { onCancel() } else { onCommit(trimmed) }
    }

    private func cancel() {
        guard !finished else { return }
        finished = true
        onCancel()
    }
}
