import SwiftUI

/// 选中绘图工具后浮在工具栏上方的属性条：颜色 + 粗细随手可点，
/// 不必再把鼠标移到右侧面板。
struct CaptureEditorOptionsBar: View {
    @Bindable var state: AnnotationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let brandBlue = Color(red: 5 / 255, green: 56 / 255, blue: 224 / 255)
    private let iconIdle = Color(red: 0.36, green: 0.39, blue: 0.45)
    private let widths: [CGFloat] = [2, 4, 6, 8]

    private var showsColors: Bool {
        state.activeKind != .mosaic
    }

    private var showsWidths: Bool {
        guard let kind = state.activeKind else { return false }
        return kind != .text && kind != .mosaic && kind != .highlight
    }

    var body: some View {
        HStack(spacing: 10) {
            if showsColors {
                HStack(spacing: 6) {
                    ForEach(0..<AnnotationPalette.count, id: \.self) { index in
                        Circle()
                            .fill(AnnotationPalette[index])
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                            .overlay {
                                if state.colorIndex == index {
                                    Circle()
                                        .strokeBorder(brandBlue, lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                        .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                                }
                            }
                            .contentShape(Circle())
                            .onTapGesture {
                                LensoAnimations.withMotion(LensoAnimations.hover, reduceMotion: reduceMotion) {
                                    state.colorIndex = index
                                }
                            }
                            .help("颜色")
                    }
                }
                .lensoAnimation(LensoAnimations.hover, value: state.colorIndex, reduceMotion: reduceMotion)
                .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }

            if showsColors && showsWidths {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 1, height: 16)
                    .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }

            if showsWidths {
                HStack(spacing: 2) {
                    ForEach(widths, id: \.self) { width in
                        Circle()
                            .fill(state.strokeWidth == width ? brandBlue : iconIdle)
                            .frame(width: width + 2, height: width + 2)
                            .frame(width: 24, height: 24)
                            .background {
                                if state.strokeWidth == width {
                                    Circle()
                                        .fill(Color.black.opacity(0.05))
                                        .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                                }
                            }
                            .contentShape(Circle())
                            .onTapGesture {
                                LensoAnimations.withMotion(LensoAnimations.hover, reduceMotion: reduceMotion) {
                                    state.strokeWidth = width
                                }
                            }
                            .help("粗细 \(Int(width))px")
                    }
                }
                .lensoAnimation(LensoAnimations.hover, value: state.strokeWidth, reduceMotion: reduceMotion)
                .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }

            if state.activeKind == .mosaic || state.activeKind == .highlight {
                Text(state.activeKind == .mosaic ? "框选要打码的区域" : "框选要高亮的区域")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }
        }
        .lensoAnimation(LensoAnimations.snappy, value: state.activeKind, reduceMotion: reduceMotion)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.white.opacity(0.9))
            }
        }
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
    }
}
