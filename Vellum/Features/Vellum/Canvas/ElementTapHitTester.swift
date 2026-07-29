import CoreGraphics
import VellumCore

enum ElementTapHitTester {
    static func hitTest(
        elements: [CanvasElement],
        at point: CGPoint,
        minimumHitWidth: CGFloat,
        extraRadius: CGFloat
    ) -> CanvasElement? {
        // Elements paint in array order, so the later hittable element is on top and wins.
        elements.last { element in
            switch element.content {
            case .shape:
                return ShapeHitTester.contains(
                    point,
                    in: element,
                    minimumHitWidth: minimumHitWidth,
                    extraRadius: extraRadius
                )
            case .image:
                return imageContains(point, in: element, extraRadius: extraRadius)
            case .text, .unknown:
                return false
            }
        }
    }

    private static func imageContains(
        _ point: CGPoint,
        in element: CanvasElement,
        extraRadius: CGFloat
    ) -> Bool {
        let frame = CGRect(
            x: CGFloat(element.frame.x),
            y: CGFloat(element.frame.y),
            width: CGFloat(element.frame.width),
            height: CGFloat(element.frame.height)
        )
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let inverseRotation = -CGFloat(element.rotation)
        let cosine = cos(inverseRotation)
        let sine = sin(inverseRotation)
        let translatedX = point.x - center.x
        let translatedY = point.y - center.y
        let localPoint = CGPoint(
            x: center.x + translatedX * cosine - translatedY * sine,
            y: center.y + translatedX * sine + translatedY * cosine
        )
        return frame
            .insetBy(dx: -extraRadius, dy: -extraRadius)
            .contains(localPoint)
    }
}
