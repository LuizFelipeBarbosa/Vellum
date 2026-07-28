import CoreGraphics

public struct LineAdjustConfig: Sendable {
    public var axisSnapDegrees: CGFloat
    public var minimumLength: CGFloat

    public static let `default` = LineAdjustConfig()

    /// Matches `ShapeRecognizerConfig.axisAlignSnapDegrees` so a line snaps to an axis at the
    /// same angle whether it was just recognized or is being dragged afterwards.
    public init(
        axisSnapDegrees: CGFloat = 8,
        minimumLength: CGFloat = 4
    ) {
        self.axisSnapDegrees = axisSnapDegrees
        self.minimumLength = minimumLength
    }
}

public enum ShapeLineAdjuster {
    /// Endpoint for a line anchored at `pivot` being dragged toward `rawPoint`.
    /// Snaps to exact horizontal/vertical when the pivot→raw angle is within
    /// `axisSnapDegrees` of an axis, by projecting onto that axis.
    public static func adjustedEndpoint(
        pivot: CGPoint,
        rawPoint: CGPoint,
        config: LineAdjustConfig = .default
    ) -> (point: CGPoint, isAxisSnapped: Bool) {
        guard pivot.x.isFinite,
              pivot.y.isFinite,
              rawPoint.x.isFinite,
              rawPoint.y.isFinite else {
            return (pivot, false)
        }

        let deltaX = rawPoint.x - pivot.x
        let deltaY = rawPoint.y - pivot.y
        let angle = atan2(deltaY, deltaX)
        let quarterTurn = CGFloat.pi / 2
        let nearestQuarterTurn = (angle / quarterTurn).rounded()
        let snapTolerance = max(
            0,
            config.axisSnapDegrees.isFinite ? config.axisSnapDegrees : 0
        ) * .pi / 180
        let shouldSnap = abs(angle - nearestQuarterTurn * quarterTurn) <= snapTolerance

        var point = rawPoint
        if shouldSnap {
            let axisIndex = Int(nearestQuarterTurn)
            if abs(axisIndex) % 2 == 0 {
                point.y = pivot.y
            } else {
                point.x = pivot.x
            }
        }

        let minimumLength = max(
            0,
            config.minimumLength.isFinite ? config.minimumLength : 0
        )
        let adjustedDeltaX = point.x - pivot.x
        let adjustedDeltaY = point.y - pivot.y
        let length = hypot(adjustedDeltaX, adjustedDeltaY)
        if length < minimumLength {
            if length > 0 {
                let scale = minimumLength / length
                point = CGPoint(
                    x: pivot.x + adjustedDeltaX * scale,
                    y: pivot.y + adjustedDeltaY * scale
                )
            } else {
                point = CGPoint(x: pivot.x + minimumLength, y: pivot.y)
            }
        }

        return (
            point,
            point.x == pivot.x || point.y == pivot.y
        )
    }
}
