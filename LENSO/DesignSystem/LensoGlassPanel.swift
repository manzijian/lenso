import SwiftUI

enum LensoStyle {
    static let radius: CGFloat = 22
    static let spacing: CGFloat = 12

    static let sidebarWidth: CGFloat = 180

    static func glassShape(_ radius: CGFloat = 22) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

/// 玻璃面板容器 — macOS 26 原生 glassEffect，低版本回退 ultraThinMaterial
struct LensoGlassPanel<Content: View>: View {
    var radius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .background {
                if #available(macOS 26.0, *) {
                    LensoStyle.glassShape(radius)
                        .fill(.clear)
                        .glassEffect(
                            .regular,
                            in: LensoStyle.glassShape(radius)
                        )
                } else {
                    LensoStyle.glassShape(radius)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            LensoStyle.glassShape(radius)
                                .stroke(.white.opacity(0.22), lineWidth: 1)
                        }
                }
            }
            .clipShape(LensoStyle.glassShape(radius))
    }
}
