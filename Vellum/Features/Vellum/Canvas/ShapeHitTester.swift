import CoreGraphics
import VellumCore

enum ShapeHitTester {
    static func strokedPath(
        for element: CanvasElement,
        minimumHitWidth: CGFloat,
        extraRadius: CGFloat
    ) -> CGPath? {
        guard case .shape(let shapeContent) = element.content else { return nil }

        let path = ShapeGeometry.path(
            for: shapeContent,
            in: element.frame,
            rotation: element.rotation
        )
        return path.copy(
            strokingWithWidth: hitWidth(
                for: shapeContent,
                minimumHitWidth: minimumHitWidth,
                extraRadius: extraRadius
            ),
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        )
    }

    /// Bounds `strokedPath(for:)` cannot reach outside of: the element's rotated frame grown by
    /// the stroking half-width. Callers on hot paths use it to reject far-away shapes before
    /// paying for the stroking, which dominates the cost of a hit test.
    static func hitBounds(
        for element: CanvasElement,
        minimumHitWidth: CGFloat,
        extraRadius: CGFloat
    ) -> CGRect? {
        guard case .shape(let shapeContent) = element.content else { return nil }

        let halfHitWidth = hitWidth(
            for: shapeContent,
            minimumHitWidth: minimumHitWidth,
            extraRadius: extraRadius
        ) / 2
        return element.rotatedBoundingBox
            .standardized
            .insetBy(dx: -halfHitWidth, dy: -halfHitWidth)
    }

    static func hitTest(
        elements: [CanvasElement],
        at point: CGPoint,
        minimumHitWidth: CGFloat,
        extraRadius: CGFloat
    ) -> CanvasElement? {
        // Elements paint in array order, so where two shapes overlap the later one is on top
        // and is the one the tap should pick.
        elements.last { element in
            strokedPath(
                for: element,
                minimumHitWidth: minimumHitWidth,
                extraRadius: extraRadius
            )?.contains(point) == true
        }
    }

    private static func hitWidth(
        for content: ShapeContent,
        minimumHitWidth: CGFloat,
        extraRadius: CGFloat
    ) -> CGFloat {
        max(CGFloat(content.strokeWidth), minimumHitWidth) + extraRadius
    }
}
