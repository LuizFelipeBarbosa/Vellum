import CoreGraphics
import Foundation

public enum ShapeGeometry {
    /// Path in absolute content coordinates; rotation (radians) applied about the frame center.
    public static func path(
        for content: ShapeContent,
        in frame: CanvasRect,
        rotation: Double
    ) -> CGPath {
        let path: CGPath
        switch content.geometry {
        case .polyline(_, let isClosed):
            let mutablePath = CGMutablePath()
            let vertices = unrotatedVertices(for: content, in: frame)
            if let firstVertex = vertices.first {
                mutablePath.move(to: firstVertex)
                for vertex in vertices.dropFirst() {
                    mutablePath.addLine(to: vertex)
                }
                if isClosed {
                    mutablePath.closeSubpath()
                }
            }
            path = mutablePath
        case .ellipse:
            path = CGPath(ellipseIn: frame.cgRect, transform: nil)
        }

        guard rotation != 0 else { return path }

        let center = CGPoint(x: frame.cgRect.midX, y: frame.cgRect.midY)
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(rotation))
            .translatedBy(x: -center.x, y: -center.y)
        return path.copy(using: &transform) ?? path
    }

    /// Denormalized polyline vertices in unrotated content space (empty for .ellipse).
    public static func unrotatedVertices(
        for content: ShapeContent,
        in frame: CanvasRect
    ) -> [CGPoint] {
        guard case .polyline(let vertices, _) = content.geometry else { return [] }

        return vertices.map { vertex in
            CGPoint(
                x: CGFloat(frame.x + vertex.x * frame.width),
                y: CGFloat(frame.y + vertex.y * frame.height)
            )
        }
    }
}

private extension CanvasRect {
    var cgRect: CGRect {
        CGRect(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
}
