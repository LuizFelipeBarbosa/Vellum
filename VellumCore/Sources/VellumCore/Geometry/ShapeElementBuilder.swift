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
            let centerX = center.x.isFinite ? Double(center.x) : 0
            let centerY = center.y.isFinite ? Double(center.y) : 0
            let horizontalRadius = radiusX.isFinite ? abs(Double(radiusX)) : 0
            let verticalRadius = radiusY.isFinite ? abs(Double(radiusY)) : 0
            let rawFrame = AxisBounds(
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
        guard let first = vertices.first else {
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

        var bounds = AxisBounds(
            minimumX: Double(first.x),
            maximumX: Double(first.x),
            minimumY: Double(first.y),
            maximumY: Double(first.y)
        )
        for vertex in vertices.dropFirst() {
            bounds.minimumX = min(bounds.minimumX, Double(vertex.x))
            bounds.maximumX = max(bounds.maximumX, Double(vertex.x))
            bounds.minimumY = min(bounds.minimumY, Double(vertex.y))
            bounds.maximumY = max(bounds.maximumY, Double(vertex.y))
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

    private static func inflatedFrame(for bounds: AxisBounds) -> CanvasRect {
        let rawWidth = bounds.maximumX - bounds.minimumX
        let rawHeight = bounds.maximumY - bounds.minimumY
        let width = max(rawWidth, minimumFrameExtent)
        let height = max(rawHeight, minimumFrameExtent)
        let midpointX = (bounds.minimumX + bounds.maximumX) / 2
        let midpointY = (bounds.minimumY + bounds.maximumY) / 2
        return CanvasRect(
            x: midpointX - width / 2,
            y: midpointY - height / 2,
            width: width,
            height: height
        )
    }

    private struct AxisBounds {
        var minimumX: Double
        var maximumX: Double
        var minimumY: Double
        var maximumY: Double
    }
}
