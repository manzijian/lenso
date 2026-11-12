import AppKit
import SwiftUI

// MARK: - 工具按钮

struct ToolIcon: View {
    let icon: String
    let kind: AnnotationKind?
    let state: AnnotationState
    var disabled = false
    let action: () -> Void

    @State private var hovering = false

    private var isActive: Bool {
        guard let kind else { return false }
        return state.activeKind == kind
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isActive ? Color(nsColor: .controlAccentColor) : (hovering ? .black : Color(red: 0.18, green: 0.18, blue: 0.22)))
            .opacity(disabled ? 0.35 : 1)
            .frame(width: 32, height: 32)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlAccentColor).opacity(0.15))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06))
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture { guard !disabled else { return }; action() }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
    }
}

// MARK: - 截图编辑器底部工具栏

struct CaptureEditorToolbarView: View {
    @Bindable var state: AnnotationState
    @Binding var isSidePanelVisible: Bool
    @Binding var panelTab: PanelTab
    let ocrPhase: OCRPhase
    let onRunOCR: () -> Void
    let onPin: () -> Void
    let onFinish: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // 选择工具（默认激活，蓝色圆底）
            ZStack {
                Circle()
                    .fill(state.activeKind == nil ? Color(nsColor: .controlAccentColor) : .clear)
                    .frame(width: 30, height: 30)
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state.activeKind == nil ? .white : Color(red: 0.18, green: 0.18, blue: 0.22))
            }
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
            .onTapGesture { state.activeKind = nil }

            ForEach([AnnotationKind.rect, .ellipse, .arrow, .brush, .text, .mosaic, .highlight], id: \.self) { kind in
                ToolIcon(icon: kind.icon, kind: kind, state: state) {
                    state.activeKind = state.activeKind == kind ? nil : kind
                    if kind == .mosaic { state.mosaicEnabled = true }
                    if kind == .highlight { state.highlightEnabled = true }
                }
            }

            Divider().frame(height: 22)

            ToolIcon(icon: "arrow.uturn.backward", kind: nil, state: state, disabled: !state.canUndo) { state.undo() }
            ToolIcon(icon: "arrow.uturn.forward", kind: nil, state: state, disabled: !state.canRedo) { state.redo() }

            // OCR 快捷入口：点按直接打开 OCR 卡片
            ToolIcon(icon: "doc.text.viewfinder", kind: nil, state: state) {
                if isSidePanelVisible && panelTab == .ocr {
                    isSidePanelVisible = false
                } else {
                    isSidePanelVisible = true
                    panelTab = .ocr
                    if ocrPhase == .idle { onRunOCR() }
                }
            }
            .help("文字识别（OCR）")

            // 钉图：把当前合成结果钉在屏幕最上层
            Image(systemName: "pin.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .onTapGesture { onPin() }
                .help("钉在屏幕上")

            Text("完成")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(nsColor: .controlAccentColor)))
                .onTapGesture { onFinish() }

            // 丢弃本次截图（不保存）
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.22))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.06)))
                .contentShape(Rectangle())
                .onTapGesture { onDiscard() }
                .help("取消截图（Esc）")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            // 实体高亮白底（不透底），无论在多么黑的终端或壁纸上都始终清晰高亮
            Capsule()
                .fill(Color(red: 0.985, green: 0.988, blue: 1.0))
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 5)
    }
}
