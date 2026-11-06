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
            let strokeStyle = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)

            for (startAngle, endAngle) in [(100.0, 282.0), (292.0, 460.0)] {
                var aperture = Path()
                aperture.addArc(
                    center: center,
                    radius: outerRadius,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(endAngle),
                    clockwise: false
                )
                context.stroke(aperture, with: .color(color), style: strokeStyle)
            }

            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - innerRadius,
                    y: center.y - innerRadius,
                    width: innerRadius * 2,
                    height: innerRadius * 2
                )),
                with: .color(color)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("LENSO")
    }
}
