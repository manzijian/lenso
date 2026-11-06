import SwiftUI

struct LensoMark: View {
    enum Rendering { case template }
    let rendering: Rendering

    init(rendering: Rendering = .template) {
        self.rendering = rendering
    }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = side * 0.34
            let innerRadius = side * 0.13
            let strokeWidth = side * 0.13
            let color = Color.primary

            var aperture = Path()
            aperture.addArc(center: center, radius: outerRadius, startAngle: .degrees(28), endAngle: .degrees(154), clockwise: false)
            aperture.addArc(center: center, radius: outerRadius, startAngle: .degrees(208), endAngle: .degrees(334), clockwise: false)
            context.stroke(aperture, with: .color(color), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))

            context.fill(
                Path(ellipseIn: CGRect(x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2)),
                with: .color(color)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("LENSO")
    }
}
