import SwiftUI

/// 收藏星标：未收藏为空心，收藏后为黄色实心
struct FavoriteStarButton: View {
    let isFavorite: Bool
    var size: CGFloat = 13
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.yellow : Color.primary.opacity(hovering ? 0.85 : 0.4))
                .lensoSymbolReplace()
                .symbolEffect(.bounce, value: reduceMotion ? false : isFavorite)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(hovering || isFavorite ? 0.92 : 0.55)))
                .contentShape(Circle())
        }
        .buttonStyle(LensoPressButtonStyle())
        .onHover { hovering = $0 }
        .lensoAnimation(LensoAnimations.hover, value: hovering, reduceMotion: reduceMotion)
        .lensoAnimation(LensoAnimations.snappy, value: isFavorite, reduceMotion: reduceMotion)
        .help(isFavorite ? "取消收藏" : "收藏")
        .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")
    }
}
