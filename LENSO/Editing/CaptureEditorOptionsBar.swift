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

    @State private var hoveringColor: Int?
    @State private var hoveringWidth: CGFloat?

    var body: some View {
        HStack(spacing: 10) {
            if showsColors {
                HStack(spacing: 4) {
                    ForEach(0..<AnnotationPalette.count, id: \.self) { index in
                        let isSelected = state.colorIndex == index
                        let isHovering = hoveringColor == index
                        Circle()
                            .fill(AnnotationPalette[index])
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                            .scaleEffect(isHovering && !isSelected ? 1.12 : 1)
                            .frame(width: 22, height: 22)
                            .overlay {
                                if isSelected {
                                    Circle()
                                        .strokeBorder(brandBlue, lineWidth: 2)
                                        .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                                } else if isHovering {
                                    Circle()
                                        .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
                                }
                            }
                            .contentShape(Circle())
                            .onHover { hovering in
                                hoveringColor = hovering ? index : (hoveringColor == index ? nil : hoveringColor)
                            }
                            .onTapGesture {
                                LensoAnimations.withMotion(LensoAnimations.hover, reduceMotion: reduceMotion) {
                                    state.colorIndex = index
                                }
                            }
                            .help("颜色")
                    }
                }
                .lensoAnimation(LensoAnimations.hover, value: hoveringColor, reduceMotion: reduceMotion)
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
                        let isSelected = state.strokeWidth == width
                        let isHovering = hoveringWidth == width
                        Circle()
                            .fill(isSelected ? brandBlue : iconIdle)
                            .frame(width: width + 2, height: width + 2)
                            .frame(width: 24, height: 24)
                            .background {
                                if isSelected {
                                    Circle()
                                        .fill(Color.black.opacity(0.06))
                                        .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
                                } else if isHovering {
                                    Circle()
                                        .fill(Color.black.opacity(0.04))
                                }
                            }
                            .contentShape(Circle())
                            .onHover { hovering in
                                hoveringWidth = hovering ? width : (hoveringWidth == width ? nil : hoveringWidth)
                            }
                            .onTapGesture {
                                LensoAnimations.withMotion(LensoAnimations.hover, reduceMotion: reduceMotion) {
                                    state.strokeWidth = width
                                }
                            }
                            .help("粗细 \(Int(width))px")
                    }
                }
                .lensoAnimation(LensoAnimations.hover, value: hoveringWidth, reduceMotion: reduceMotion)
                .lensoAnimation(LensoAnimations.hover, value: state.strokeWidth, reduceMotion: reduceMotion)
                .transition(LensoTransitions.badge(reduceMotion: reduceMotion))
            }

            if state.activeKind == .mosaic || state.activeKind == .highlight {
                Text(state.activeKind == .mosaic ? "框选要打码的区域" : "框选要高亮的区域")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
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
