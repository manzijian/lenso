import AppKit
import SwiftUI

// MARK: - 品牌色与工具按钮

/// 克莱因蓝：与主界面同一支品牌色，避免工具栏里混用系统蓝
private let brandBlue = Color(red: 5 / 255, green: 56 / 255, blue: 224 / 255)
private let brandBlueDeep = Color(red: 33 / 255, green: 80 / 255, blue: 240 / 255)
private let iconIdle = Color(red: 0.29, green: 0.32, blue: 0.38)

struct ToolIcon: View {
    let icon: String
    let kind: AnnotationKind?
    let state: AnnotationState
    var disabled = false
    var tooltip: String? = nil
    let action: () -> Void

    @State private var hovering = false

    private var isActive: Bool {
        guard let kind else { return false }
        return state.activeKind == kind
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(isActive ? brandBlue : iconIdle)
            .opacity(disabled ? 0.3 : 1)
            .frame(width: 30, height: 30)
            .background {
                if isActive {
                    // 浮起的白胶囊：靠内高光与轻投影立起来，不用实心色块
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5))
                } else if hovering && !disabled {
                    Circle().fill(Color.black.opacity(0.05))
                }
            }
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .onTapGesture { guard !disabled else { return }; action() }
            .help(tooltip ?? "")
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: isActive)
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
        HStack(spacing: 2) {
            // 选择工具：与其它工具同一套选中语言（白胶囊 + 蓝图标）
            ToolIcon(
                icon: "cursorarrow",
                kind: nil,
                state: state,
                tooltip: "选择 / 移动"
            ) {
                state.activeKind = nil
            }
            .overlay {
                if state.activeKind == nil {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(brandBlue)
                        .frame(width: 30, height: 30)
                        .background {
                            Circle()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5))
                        }
                        .allowsHitTesting(false)
                }
            }

            ForEach([AnnotationKind.rect, .ellipse, .arrow, .brush, .text, .mosaic, .highlight], id: \.self) { kind in
                ToolIcon(icon: kind.icon, kind: kind, state: state, tooltip: kind.label) {
                    state.activeKind = state.activeKind == kind ? nil : kind
                    if kind == .mosaic { state.mosaicEnabled = true }
                    if kind == .highlight { state.highlightEnabled = true }
                }
            }

            separator

            ToolIcon(icon: "arrow.uturn.backward", kind: nil, state: state, disabled: !state.canUndo, tooltip: "撤销 ⌘Z") {
                state.undo()
            }
            ToolIcon(icon: "arrow.uturn.forward", kind: nil, state: state, disabled: !state.canRedo, tooltip: "重做 ⇧⌘Z") {
                state.redo()
            }

            separator

            // OCR 快捷入口
            ToolIcon(icon: "doc.text.viewfinder", kind: nil, state: state, tooltip: "文字识别（OCR）") {
                if isSidePanelVisible && panelTab == .ocr {
                    isSidePanelVisible = false
                } else {
                    isSidePanelVisible = true
                    panelTab = .ocr
                    if ocrPhase == .idle { onRunOCR() }
                }
            }

            ToolIcon(icon: "pin", kind: nil, state: state, tooltip: "钉在屏幕上") {
                onPin()
            }

            ToolIcon(icon: "xmark", kind: nil, state: state, tooltip: "取消截图（Esc）") {
                onDiscard()
            }

            finishButton
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background {
            // 玻璃浮岛：上缘高光 + 半透明材质，让背后的画面透一点进来
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.86), Color.white.opacity(0.74)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.75), lineWidth: 0.5)
            )
            .overlay(
                Capsule().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
            )
        }
        .shadow(color: .black.opacity(0.20), radius: 26, y: 8)
        .shadow(color: .black.opacity(0.10), radius: 50, y: 22)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 5)
    }

    private var finishButton: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9.5, weight: .bold))
            Text("完成")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(
            Capsule()
                .fill(LinearGradient(colors: [brandBlueDeep, brandBlue], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: brandBlue.opacity(0.34), radius: 8, y: 2)
        .padding(.leading, 4)
        .contentShape(Capsule())
        .onTapGesture { onFinish() }
        .help("完成并保存（⏎）")
    }
}
