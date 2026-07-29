import CoreGraphics
import VellumCore

enum ElementTapHitTester {
    /// Shared by every tap surface so finger-tap hit behavior can't drift between tool modes.
    static let defaultMinimumHitWidth: CGFloat = 4
    static let defaultTouchHitRadius: CGFloat = 12

    static func hitTest(
        elements: [CanvasElement],
        at point: CGPoint,
        minimumHitWidth: CGFloat = ElementTapHitTester.defaultMinimumHitWidth,
        extraRadius: CGFloat = ElementTapHitTester.defaultTouchHitRadius
    ) -> CanvasElement? {
        // Elements paint in effective z-order: below ink, then ink, then above ink.
        // Array order breaks ties within a placement, so the topmost hittable element wins.
        elements.sortedByEffectiveZ().last { element in
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
