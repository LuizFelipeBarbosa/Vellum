import SwiftUI

/// The Vellum brand mark: a two-stroke letter V with round caps,
/// left stroke ink, right stroke ochre. Drawn in a 48×48 design space.
struct VellumLogoMark: View {
    let size: CGFloat
    var onDark = false

    private var leftStroke: Color { onDark ? VellumTheme.paper : VellumTheme.ink }
    private var rightStroke: Color { onDark ? Color(hex: "#C98B45") : VellumTheme.accent }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 48
            // Brand rule: at rendered sizes ≤32pt the strokes thicken to stay legible.
            let lineWidth = (size <= 32 ? 9.0 : 6.0) * scale
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

            var left = Path()
            left.move(to: CGPoint(x: 11 * scale, y: 9 * scale))
            left.addLine(to: CGPoint(x: 24 * scale, y: 39 * scale))
            context.stroke(left, with: .color(leftStroke), style: style)

            var right = Path()
            right.move(to: CGPoint(x: 37 * scale, y: 9 * scale))
            right.addLine(to: CGPoint(x: 24 * scale, y: 39 * scale))
            context.stroke(right, with: .color(rightStroke), style: style)
        }
        .frame(width: size, height: size)
    }
}
