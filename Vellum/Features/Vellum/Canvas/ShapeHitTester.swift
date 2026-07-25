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
            strokingWithWidth: max(
                CGFloat(shapeContent.strokeWidth),
                minimumHitWidth
            ) + extraRadius,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        )
    }

    static func hitTest(
        elements: [CanvasElement],
        at point: CGPoint,
        minimumHitWidth: CGFloat,
        extraRadius: CGFloat
    ) -> CanvasElement? {
        elements.first { element in
            strokedPath(
                for: element,
                minimumHitWidth: minimumHitWidth,
                extraRadius: extraRadius
            )?.contains(point) == true
        }
    }
}
