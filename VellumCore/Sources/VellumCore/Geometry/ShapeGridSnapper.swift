import CoreGraphics

/// The lattice a recognized shape snaps to: the same rules, grid lines, or dots
/// `PageBackgroundPattern` draws for the page under the shape.
public struct ShapeSnapGrid: Equatable, Sendable {
    /// Page origin in content space. The lattice is measured from here, not from the canvas.
    public var origin: CGPoint
    public var spacing: CGFloat
    public var snapsX: Bool
    public var snapsY: Bool
    /// How far a coordinate may be pulled. Capped well below half a step so deliberate
    /// off-lattice placement survives.
    public var tolerance: CGFloat
    /// Index of the first drawn line on each axis — rules and grid lines start one step in,
    /// dots start at the page edge.
    public var firstIndex: Int

    public static func defaultTolerance(forSpacing spacing: CGFloat) -> CGFloat {
        min(8, max(0, spacing) * 0.3)
    }

    public init(
        origin: CGPoint,
        spacing: CGFloat,
        snapsX: Bool,
        snapsY: Bool,
        tolerance: CGFloat? = nil,
        firstIndex: Int = 0
    ) {
        self.origin = origin
        self.spacing = spacing
        self.snapsX = snapsX
        self.snapsY = snapsY
        self.tolerance = tolerance ?? Self.defaultTolerance(forSpacing: spacing)
        self.firstIndex = firstIndex
    }
}

public enum ShapeGridSnapper {
    /// Angular slack, in radians, within which a shape counts as axis-aligned.
    private static let axisEpsilon: CGFloat = 0.001

    /// The lattice for a page, or nil when the page has nothing to align to.
    public static func grid(
        for style: PageBackgroundStyle,
        pageRect: CGRect
    ) -> ShapeSnapGrid? {
        guard pageRect.origin.x.isFinite, pageRect.origin.y.isFinite else { return nil }

        let spacing = CGFloat(PageBackgroundStyle.clampedSpacing(style.spacing))
        guard spacing > 0 else { return nil }

        switch style.kind {
        case .blank:
            return nil
        case .ruled:
            return ShapeSnapGrid(
                origin: pageRect.origin,
                spacing: spacing,
                snapsX: false,
                snapsY: true,
                firstIndex: 1
            )
        case .grid:
            return ShapeSnapGrid(
                origin: pageRect.origin,
                spacing: spacing,
                snapsX: true,
                snapsY: true,
                firstIndex: 1
            )
        case .dots:
            return ShapeSnapGrid(
                origin: pageRect.origin,
                spacing: spacing,
                snapsX: true,
                snapsY: true,
                firstIndex: 0
            )
        }
    }

    /// Pulls an axis-aligned shape onto the lattice. Tilted shapes are returned untouched: their
    /// corners would each snap in a different direction and the shape would be distorted rather
    /// than aligned.
    public static func snapped(
        _ shape: RecognizedShape,
        to grid: ShapeSnapGrid?
    ) -> RecognizedShape {
        guard let grid, grid.snapsX || grid.snapsY, grid.spacing > 0 else { return shape }

        switch shape {
        case .polyline(let vertices, true):
            // A closed shape is moved onto the lattice rather than stretched onto it: the
            // recognizer has just squared its corners and evened its sides, and snapping each
            // edge independently would undo that.
            guard isAxisAligned(vertices, isClosed: true),
                  let offset = latticeOffset(forBoundsOf: vertices, grid: grid) else {
                return shape
            }
            return .polyline(
                vertices: vertices.map {
                    CGPoint(x: $0.x + offset.dx, y: $0.y + offset.dy)
                },
                isClosed: true
            )
        case .polyline(let vertices, false):
            guard isAxisAligned(vertices, isClosed: false) else { return shape }
            // An open line has no proportions to protect, so its ends settle individually: the
            // run lands on a rule and, on a grid, its ends land on columns.
            return .polyline(
                vertices: vertices.map { snappedPoint($0, to: grid) },
                isClosed: false
            )
        case .ellipse(let center, let radiusX, let radiusY, let rotation):
            return snappedEllipse(
                center: center,
                radiusX: radiusX,
                radiusY: radiusY,
                rotation: rotation,
                grid: grid
            )
        }
    }

    /// How far a shape must move for the minimum corner of its bounding box to sit on the
    /// lattice, or nil when neither axis is close enough to be worth moving.
    private static func latticeOffset(
        forBoundsOf points: [CGPoint],
        grid: ShapeSnapGrid
    ) -> CGVector? {
        guard let minimumX = points.map(\.x).min(),
              let minimumY = points.map(\.y).min() else {
            return nil
        }
        let corner = snappedPoint(CGPoint(x: minimumX, y: minimumY), to: grid)
        let offset = CGVector(dx: corner.x - minimumX, dy: corner.y - minimumY)
        guard offset.dx != 0 || offset.dy != 0 else { return nil }
        return offset
    }

    public static func snappedPoint(_ point: CGPoint, to grid: ShapeSnapGrid?) -> CGPoint {
        guard let grid, grid.spacing > 0 else { return point }
        return CGPoint(
            x: grid.snapsX
                ? snappedCoordinate(point.x, origin: grid.origin.x, grid: grid)
                : point.x,
            y: grid.snapsY
                ? snappedCoordinate(point.y, origin: grid.origin.y, grid: grid)
                : point.y
        )
    }

    static func snappedCoordinate(
        _ value: CGFloat,
        origin: CGFloat,
        grid: ShapeSnapGrid
    ) -> CGFloat {
        guard value.isFinite, origin.isFinite else { return value }

        let index = max(
            CGFloat(grid.firstIndex),
            ((value - origin) / grid.spacing).rounded()
        )
        let candidate = origin + index * grid.spacing
        return abs(candidate - value) <= max(0, grid.tolerance) ? candidate : value
    }

    static func isAxisAligned(_ vertices: [CGPoint], isClosed: Bool) -> Bool {
        guard vertices.count >= 2 else { return false }

        let lastEdgeIndex = isClosed ? vertices.count - 1 : vertices.count - 2
        guard lastEdgeIndex >= 0 else { return false }

        for index in 0...lastEdgeIndex {
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]
            let isHorizontal = abs(end.y - start.y) <= axisEpsilon
            let isVertical = abs(end.x - start.x) <= axisEpsilon
            guard isHorizontal || isVertical else { return false }
        }
        return true
    }

    private static func snappedEllipse(
        center: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        rotation: CGFloat,
        grid: ShapeSnapGrid
    ) -> RecognizedShape {
        let unchanged = RecognizedShape.ellipse(
            center: center,
            radiusX: radiusX,
            radiusY: radiusY,
            rotation: rotation
        )

        // Only an ellipse standing square to the page has a bounding box worth aligning; at a
        // quarter turn it still does, with its radii swapped.
        guard let quarterTurn = QuarterTurn(nearest: rotation, tolerance: axisEpsilon) else {
            return unchanged
        }
        let isQuarterTurned = quarterTurn.swapsAxes
        let halfWidth = isQuarterTurned ? radiusY : radiusX
        let halfHeight = isQuarterTurned ? radiusX : radiusY

        // Moved, not stretched — the same reason a closed polygon is: resizing the axes
        // separately would turn a circle the recognizer just rounded back into an ellipse.
        guard let offset = latticeOffset(
            forBoundsOf: [
                CGPoint(x: center.x - halfWidth, y: center.y - halfHeight),
                CGPoint(x: center.x + halfWidth, y: center.y + halfHeight),
            ],
            grid: grid
        ) else {
            return unchanged
        }

        return .ellipse(
            center: CGPoint(x: center.x + offset.dx, y: center.y + offset.dy),
            radiusX: radiusX,
            radiusY: radiusY,
            rotation: rotation
        )
    }
}
