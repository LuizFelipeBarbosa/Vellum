import CoreGraphics

/// The axis-aligned extent of a set of points, in content space.
struct PointBounds {
    let minimumX: CGFloat
    let maximumX: CGFloat
    let minimumY: CGFloat
    let maximumY: CGFloat

    var width: CGFloat { maximumX - minimumX }
    var height: CGFloat { maximumY - minimumY }
    var diagonal: CGFloat { hypot(width, height) }

    var midpoint: CGPoint {
        CGPoint(x: (minimumX + maximumX) / 2, y: (minimumY + maximumY) / 2)
    }
}

extension PointBounds {
    /// nil when there is nothing to bound, or when any coordinate is non-finite: an
    /// extent computed from NaN is not an extent, and every caller reads "no bounds"
    /// as "leave the shape as it is".
    init?(of points: [CGPoint]) {
        guard let first = points.first,
              first.x.isFinite,
              first.y.isFinite else {
            return nil
        }

        var minimumX = first.x
        var maximumX = first.x
        var minimumY = first.y
        var maximumY = first.y
        for point in points.dropFirst() {
            guard point.x.isFinite, point.y.isFinite else { return nil }
            minimumX = min(minimumX, point.x)
            maximumX = max(maximumX, point.x)
            minimumY = min(minimumY, point.y)
            maximumY = max(maximumY, point.y)
        }
        self.init(
            minimumX: minimumX,
            maximumX: maximumX,
            minimumY: minimumY,
            maximumY: maximumY
        )
    }
}
