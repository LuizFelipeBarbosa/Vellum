import CoreGraphics
import Foundation

/// Editing for ellipses, which have no vertices to grab. Handles sit on the curve itself at the
/// ends of each axis, so an ellipse is resized by pulling the shape rather than a box around it.
public enum ShapeEllipseEditor {
    /// Handle order: top, right, bottom, left of the unrotated frame.
    public static let handleCount = 4

    /// World-space (rotated) handle positions.
    public static func radiusHandles(frame: CanvasRect, rotation: Double) -> [CGPoint] {
        guard rotation.isFinite,
              frame.x.isFinite,
              frame.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite else {
            return []
        }

        let center = CGPoint(
            x: CGFloat(frame.x + frame.width / 2),
            y: CGFloat(frame.y + frame.height / 2)
        )
        let handles = [
            CGPoint(x: center.x, y: CGFloat(frame.y)),
            CGPoint(x: CGFloat(frame.x + frame.width), y: center.y),
            CGPoint(x: center.x, y: CGFloat(frame.y + frame.height)),
            CGPoint(x: CGFloat(frame.x), y: center.y),
        ]
        guard rotation != 0 else { return handles }

        let angle = CGFloat(rotation)
        let cosine = cos(angle)
        let sine = sin(angle)
        return handles.map {
            ShapeGeometry.rotated($0, around: center, cosine: cosine, sine: sine)
        }
    }

    /// Pull one axis of the ellipse to `worldPoint`. The opposite point on the curve and the
    /// other axis keep their rendered positions, so only the radius being dragged changes.
    public static func resizing(
        handleIndex: Int,
        to worldPoint: CGPoint,
        frame: CanvasRect,
        rotation: Double
    ) -> CanvasRect? {
        guard (0..<handleCount).contains(handleIndex),
              worldPoint.x.isFinite,
              worldPoint.y.isFinite,
              rotation.isFinite,
              frame.x.isFinite,
              frame.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite else {
            return nil
        }

        let angle = CGFloat(rotation)
        let cosine = cos(angle)
        let sine = sin(angle)
        let oldCenter = CGPoint(
            x: CGFloat(frame.x + frame.width / 2),
            y: CGFloat(frame.y + frame.height / 2)
        )
        let local = ShapeGeometry.inverseRotated(
            worldPoint,
            around: oldCenter,
            cosine: cosine,
            sine: sine
        )

        let minimumExtent = CGFloat(ShapeElementBuilder.minimumFrameExtent)
        var minimumX = CGFloat(frame.x)
        var minimumY = CGFloat(frame.y)
        var maximumX = CGFloat(frame.x + frame.width)
        var maximumY = CGFloat(frame.y + frame.height)

        switch handleIndex {
        case 0:
            minimumY = min(local.y, maximumY - minimumExtent)
        case 1:
            maximumX = max(local.x, minimumX + minimumExtent)
        case 2:
            maximumY = max(local.y, minimumY + minimumExtent)
        default:
            minimumX = min(local.x, maximumX - minimumExtent)
        }

        let width = maximumX - minimumX
        let height = maximumY - minimumY
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }

        let newCenter = CGPoint(x: minimumX + width / 2, y: minimumY + height / 2)
        let compensation = ShapeGeometry.rotationCompensation(
            forCenterDelta: CGPoint(
                x: newCenter.x - oldCenter.x,
                y: newCenter.y - oldCenter.y
            ),
            cosine: cosine,
            sine: sine
        )
        return CanvasRect(
            x: Double(minimumX + compensation.x),
            y: Double(minimumY + compensation.y),
            width: Double(width),
            height: Double(height)
        )
    }
}
