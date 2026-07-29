import CoreGraphics

extension CanvasElement {
    /// Returns a copy of this element reflected across the vertical axis (horizontal: true)
    /// or horizontal axis (horizontal: false) through `pivot`, in content coordinates.
    /// Elements render as translate(center) · rotate(rotation) · Local, so a reflection
    /// conjugates the rotation (negates it) and mirrors frame-local content.
    public func flipped(horizontal: Bool, aboutPivot pivot: CGPoint) -> CanvasElement {
        let centerX = frame.x + frame.width / 2
        let centerY = frame.y + frame.height / 2
        let reflectedCenterX = horizontal ? 2 * Double(pivot.x) - centerX : centerX
        let reflectedCenterY = horizontal ? centerY : 2 * Double(pivot.y) - centerY
        let reflectedFrame = CanvasRect(
            x: reflectedCenterX - frame.width / 2,
            y: reflectedCenterY - frame.height / 2,
            width: frame.width,
            height: frame.height
        )

        var reflectedContent = content
        switch reflectedContent {
        case .image(var image):
            if horizontal {
                image.flippedHorizontally.toggle()
            } else {
                image.flippedVertically.toggle()
            }
            reflectedContent = .image(image)
        case .shape(var shape):
            if case .polyline(let vertices, let isClosed) = shape.geometry {
                let reflectedVertices = vertices.map { vertex in
                    horizontal
                        ? CanvasPoint(x: 1 - vertex.x, y: vertex.y)
                        : CanvasPoint(x: vertex.x, y: 1 - vertex.y)
                }
                shape.geometry = .polyline(
                    vertices: reflectedVertices,
                    isClosed: isClosed
                )
            }
            reflectedContent = .shape(shape)
        case .text, .unknown:
            break
        }

        return CanvasElement(
            id: id,
            content: reflectedContent,
            frame: reflectedFrame,
            rotation: -rotation,
            createdAt: createdAt,
            layerPlacement: layerPlacement
        )
    }
}
