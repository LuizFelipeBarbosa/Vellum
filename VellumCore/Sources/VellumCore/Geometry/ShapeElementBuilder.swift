import CoreGraphics

public enum ShapeElementBuilder {
    public static let minimumFrameExtent: Double = 8

    /// Normalize a recognized shape into the storage conventions used by ShapeGeometry.
    public static func element(
        from shape: RecognizedShape,
        strokeColor: CodableColor,
        strokeWidth: Double
    ) -> (content: ShapeContent, frame: CanvasRect, rotation: Double) {
        switch shape {
        case .polyline(let vertices, let isClosed):
            let finiteVertices = vertices.filter { $0.x.isFinite && $0.y.isFinite }
            let geometry = normalizedGeometry(for: finiteVertices)
            return (
                content: ShapeContent(
                    geometry: .polyline(
                        vertices: geometry.vertices,
                        isClosed: isClosed
                    ),
                    strokeColor: strokeColor,
                    strokeWidth: strokeWidth
                ),
                frame: geometry.frame,
                rotation: 0
            )

        case .ellipse(let center, let radiusX, let radiusY, let rotation):
            let centerX = center.x.isFinite ? center.x : 0
            let centerY = center.y.isFinite ? center.y : 0
            let horizontalRadius = radiusX.isFinite ? abs(radiusX) : 0
            let verticalRadius = radiusY.isFinite ? abs(radiusY) : 0
            let rawFrame = PointBounds(
                minimumX: centerX - horizontalRadius,
                maximumX: centerX + horizontalRadius,
                minimumY: centerY - verticalRadius,
                maximumY: centerY + verticalRadius
            )
            return (
                content: ShapeContent(
                    geometry: .ellipse,
                    strokeColor: strokeColor,
                    strokeWidth: strokeWidth
                ),
                frame: inflatedFrame(for: rawFrame),
                rotation: rotation.isFinite ? Double(rotation) : 0
            )
        }
    }

    private static func normalizedGeometry(
        for vertices: [CGPoint]
    ) -> (vertices: [CanvasPoint], frame: CanvasRect) {
        guard let bounds = PointBounds(of: vertices) else {
            return (
                vertices: [],
                frame: CanvasRect(
                    x: -minimumFrameExtent / 2,
                    y: -minimumFrameExtent / 2,
                    width: minimumFrameExtent,
                    height: minimumFrameExtent
                )
            )
        }

        let frame = inflatedFrame(for: bounds)
        let horizontalCollapsed = bounds.maximumX == bounds.minimumX
        let verticalCollapsed = bounds.maximumY == bounds.minimumY
        let normalized = vertices.map { vertex in
            CanvasPoint(
                x: horizontalCollapsed
                    ? 0.5
                    : (Double(vertex.x) - frame.x) / frame.width,
                y: verticalCollapsed
                    ? 0.5
                    : (Double(vertex.y) - frame.y) / frame.height
            )
        }
        return (vertices: normalized, frame: frame)
    }

    private static func inflatedFrame(for bounds: PointBounds) -> CanvasRect {
        let width = max(Double(bounds.width), minimumFrameExtent)
        let height = max(Double(bounds.height), minimumFrameExtent)
        let midpoint = bounds.midpoint
        return CanvasRect(
            x: Double(midpoint.x) - width / 2,
            y: Double(midpoint.y) - height / 2,
            width: width,
            height: height
        )
    }
}
