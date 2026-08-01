import CoreGraphics
import Testing
@testable import VellumCore

@Suite("Shape line adjuster")
struct ShapeLineAdjusterTests {
    private let pivot = CGPoint(x: 40, y: 60)
    private let accuracy: CGFloat = 0.0001

    @Test("The drag tolerance matches the one the recognizer snaps a fresh line with")
    func dragToleranceMatchesRecognition() {
        #expect(
            LineAdjustConfig.default.axisSnapDegrees
                == ShapeRecognizerConfig.default.axisAlignSnapDegrees
        )
    }

    @Test("Axis snapping respects tolerance in all four directions")
    func axisSnapToleranceInAllDirections() {
        let axisAngles: [CGFloat] = [0, 90, 180, 270]
        // Derived from the configured tolerance so the boundary is what is under test, not the
        // particular number of degrees.
        let tolerance = LineAdjustConfig.default.axisSnapDegrees

        for axisAngle in axisAngles {
            let inside = point(angleDegrees: axisAngle + tolerance - 0.1, length: 100)
            let insideResult = ShapeLineAdjuster.adjustedEndpoint(
                pivot: pivot,
                rawPoint: inside
            )
            #expect(insideResult.isAxisSnapped)
            #expect(
                insideResult.point.x == pivot.x
                    || insideResult.point.y == pivot.y
            )

            let outside = point(angleDegrees: axisAngle + tolerance + 0.1, length: 100)
            let outsideResult = ShapeLineAdjuster.adjustedEndpoint(
                pivot: pivot,
                rawPoint: outside
            )
            #expect(!outsideResult.isAxisSnapped)
            #expect(distance(outsideResult.point, outside) < accuracy)
        }
    }

    @Test("Axis snapping projects onto the selected axis")
    func axisSnapProjectsEndpoint() {
        let horizontalRawPoint = CGPoint(x: 140, y: 64)
        let horizontal = ShapeLineAdjuster.adjustedEndpoint(
            pivot: pivot,
            rawPoint: horizontalRawPoint
        )

        #expect(horizontal.isAxisSnapped)
        #expect(horizontal.point.x == horizontalRawPoint.x)
        #expect(horizontal.point.y == pivot.y)
        #expect(
            abs(distance(horizontal.point, pivot) - abs(horizontalRawPoint.x - pivot.x))
                < accuracy
        )

        let verticalRawPoint = CGPoint(x: 44, y: 160)
        let vertical = ShapeLineAdjuster.adjustedEndpoint(
            pivot: pivot,
            rawPoint: verticalRawPoint
        )

        #expect(vertical.isAxisSnapped)
        #expect(vertical.point.x == pivot.x)
        #expect(vertical.point.y == verticalRawPoint.y)
        #expect(
            abs(distance(vertical.point, pivot) - abs(verticalRawPoint.y - pivot.y))
                < accuracy
        )
    }

    @Test("A diagonal drag passes through without distortion")
    func diagonalDragPassesThrough() {
        let rawPoint = CGPoint(x: 100, y: 120)
        let result = ShapeLineAdjuster.adjustedEndpoint(
            pivot: pivot,
            rawPoint: rawPoint
        )

        #expect(!result.isAxisSnapped)
        #expect(result.point == rawPoint)
    }

    @Test("Short drags extend along their current direction")
    func minimumLengthClampPreservesDirection() {
        let rawPoint = CGPoint(x: pivot.x + 0.3, y: pivot.y + 0.4)
        let result = ShapeLineAdjuster.adjustedEndpoint(
            pivot: pivot,
            rawPoint: rawPoint
        )

        #expect(!result.isAxisSnapped)
        #expect(abs(distance(result.point, pivot) - 4) < accuracy)
        #expect(abs(result.point.x - (pivot.x + 2.4)) < accuracy)
        #expect(abs(result.point.y - (pivot.y + 3.2)) < accuracy)
    }

    @Test("A zero-length drag extends along positive x")
    func zeroLengthDragExtendsAlongPositiveX() {
        let result = ShapeLineAdjuster.adjustedEndpoint(
            pivot: pivot,
            rawPoint: pivot
        )

        #expect(result.point == CGPoint(x: pivot.x + 4, y: pivot.y))
        #expect(result.isAxisSnapped)
    }

    @Test("Non-finite inputs return the pivot without snapping")
    func nonFiniteInputsReturnPivot() {
        let rawPoints = [
            CGPoint(x: CGFloat.nan, y: 80),
            CGPoint(x: 80, y: CGFloat.infinity),
        ]
        for rawPoint in rawPoints {
            let result = ShapeLineAdjuster.adjustedEndpoint(
                pivot: pivot,
                rawPoint: rawPoint
            )
            #expect(result.point == pivot)
            #expect(!result.isAxisSnapped)
        }

        let nonFinitePivot = CGPoint(x: -CGFloat.infinity, y: 60)
        let result = ShapeLineAdjuster.adjustedEndpoint(
            pivot: nonFinitePivot,
            rawPoint: CGPoint(x: 100, y: 100)
        )
        #expect(result.point == nonFinitePivot)
        #expect(!result.isAxisSnapped)
    }

    private func point(angleDegrees: CGFloat, length: CGFloat) -> CGPoint {
        let angle = angleDegrees * .pi / 180
        return CGPoint(
            x: pivot.x + cos(angle) * length,
            y: pivot.y + sin(angle) * length
        )
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }
}
