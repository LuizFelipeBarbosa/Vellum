import CoreGraphics
import Foundation

public enum SelectionResizeMath {
    public static let centerUnit = CGPoint(x: 0.5, y: 0.5)
    public static let minimumExtent: CGFloat = 12

    /// Mirroring the handle in unit space identifies the point a resize must keep fixed.
    public static func oppositeUnit(of unit: CGPoint) -> CGPoint {
        CGPoint(x: 1 - unit.x, y: 1 - unit.y)
    }

    /// Resize handles follow the selection's committed rotation before an interaction begins.
    public static func point(
        atUnit unit: CGPoint,
        in bounds: CGRect,
        rotation: Double
    ) -> CGPoint {
        let point = CGPoint(
            x: bounds.minX + unit.x * bounds.width,
            y: bounds.minY + unit.y * bounds.height
        )
        guard rotation != 0 else { return point }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return point.applying(Self.rotation(CGFloat(rotation), about: center))
    }

    /// Projection onto the original diagonal preserves aspect ratio without discarding direction.
    public static func cornerFactor(
        handleUnit: CGPoint,
        anchorUnit: CGPoint,
        bounds: CGRect,
        rotation: Double,
        current: CGPoint
    ) -> CGFloat {
        let anchor = point(atUnit: anchorUnit, in: bounds, rotation: rotation)
        let handle = point(atUnit: handleUnit, in: bounds, rotation: rotation)
        let diagonal = CGPoint(x: handle.x - anchor.x, y: handle.y - anchor.y)
        let denominator = diagonal.x * diagonal.x + diagonal.y * diagonal.y
        guard denominator != 0 else { return 1 }

        let drag = CGPoint(x: current.x - anchor.x, y: current.y - anchor.y)
        return (drag.x * diagonal.x + drag.y * diagonal.y) / denominator
    }

    /// Keeping the signed local-axis component makes opposite edges resize symmetrically.
    public static func edgeFactor(
        handleUnit: CGPoint,
        anchorUnit: CGPoint,
        bounds: CGRect,
        rotation: Double,
        current: CGPoint,
        axisIsX: Bool
    ) -> CGFloat {
        let anchor = point(atUnit: anchorUnit, in: bounds, rotation: rotation)
        let angle = CGFloat(rotation)
        let axis = axisIsX
            ? CGPoint(x: cos(angle), y: sin(angle))
            : CGPoint(x: -sin(angle), y: cos(angle))
        let unitDelta = axisIsX
            ? handleUnit.x - anchorUnit.x
            : handleUnit.y - anchorUnit.y
        let extent = axisIsX ? bounds.width : bounds.height
        let denominator = extent * unitDelta
        guard denominator != 0 else { return 1 }

        let drag = CGPoint(x: current.x - anchor.x, y: current.y - anchor.y)
        return (drag.x * axis.x + drag.y * axis.y) / denominator
    }

    /// A shared floor for uniform scaling prevents a corner drag from changing aspect at the limit.
    public static func clampedScale(
        _ scale: CGSize,
        in bounds: CGRect,
        uniform: Bool
    ) -> CGSize {
        let minimumXScale = minimumExtent / bounds.width
        let minimumYScale = minimumExtent / bounds.height
        if uniform {
            let minimumScale = max(minimumXScale, minimumYScale)
            return CGSize(
                width: max(scale.width, minimumScale),
                height: max(scale.height, minimumScale)
            )
        }
        return CGSize(
            width: max(scale.width, minimumXScale),
            height: max(scale.height, minimumYScale)
        )
    }

    /// Conjugating through the committed rotation keeps scaling in the chrome's local axes.
    public static func transform(
        bounds: CGRect,
        anchorUnit: CGPoint,
        scale: CGSize,
        rotationDelta: Double,
        committedRotation: Double
    ) -> CGAffineTransform {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let anchor = CGPoint(
            x: bounds.minX + anchorUnit.x * bounds.width,
            y: bounds.minY + anchorUnit.y * bounds.height
        )
        let localTransform = CGAffineTransform(
            translationX: -anchor.x,
            y: -anchor.y
        )
        .concatenating(
            CGAffineTransform(scaleX: scale.width, y: scale.height)
        )
        .concatenating(
            CGAffineTransform(rotationAngle: CGFloat(rotationDelta))
        )
        .concatenating(
            CGAffineTransform(translationX: anchor.x, y: anchor.y)
        )
        guard committedRotation != 0 else { return localTransform }

        let angle = CGFloat(committedRotation)
        return rotation(-angle, about: center)
            .concatenating(localTransform)
            .concatenating(rotation(angle, about: center))
    }

    /// Deriving rendering from the interaction transform prevents the two composites from drifting.
    public static func chromeTransform(
        bounds: CGRect,
        anchorUnit: CGPoint,
        scale: CGSize,
        rotationDelta: Double,
        committedRotation: Double
    ) -> CGAffineTransform {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return rotation(CGFloat(committedRotation), about: center)
            .concatenating(
                transform(
                    bounds: bounds,
                    anchorUnit: anchorUnit,
                    scale: scale,
                    rotationDelta: rotationDelta,
                    committedRotation: committedRotation
                )
            )
    }

    private static func rotation(
        _ angle: CGFloat,
        about center: CGPoint
    ) -> CGAffineTransform {
        CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(
                CGAffineTransform(translationX: center.x, y: center.y)
            )
    }
}
