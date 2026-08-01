import CoreGraphics
import Foundation

public enum ShapeVertexEditor {
    /// World-space (rotated) vertex positions, for placing edit handles.
    public static func absoluteVertices(
        content: ShapeContent,
        frame: CanvasRect,
        rotation: Double
    ) -> [CGPoint] {
        guard rotation.isFinite,
              frame.x.isFinite,
              frame.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite else {
            return []
        }
        let vertices = ShapeGeometry.unrotatedVertices(for: content, in: frame)
        guard rotation != 0 else { return vertices }

        let angle = CGFloat(rotation)
        let cosine = cos(angle)
        let sine = sin(angle)
        let center = CGPoint(
            x: CGFloat(frame.x + frame.width / 2),
            y: CGFloat(frame.y + frame.height / 2)
        )
        return vertices.map {
            ShapeGeometry.rotated($0, around: center, cosine: cosine, sine: sine)
        }
    }

    /// Move one world-space vertex while preserving all other rendered vertex positions.
    public static func movingVertex(
        at index: Int,
        to worldPoint: CGPoint,
        content: ShapeContent,
        frame: CanvasRect,
        rotation: Double
    ) -> (content: ShapeContent, frame: CanvasRect)? {
        guard case .polyline(let storedVertices, let isClosed) = content.geometry,
              storedVertices.indices.contains(index),
              worldPoint.x.isFinite,
              worldPoint.y.isFinite,
              rotation.isFinite,
              frame.x.isFinite,
              frame.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite else {
            return nil
        }

        var unrotatedVertices = ShapeGeometry.unrotatedVertices(for: content, in: frame)
        guard unrotatedVertices.count == storedVertices.count else { return nil }

        let angle = CGFloat(rotation)
        let cosine = cos(angle)
        let sine = sin(angle)
        let oldCenter = CGPoint(
            x: CGFloat(frame.x + frame.width / 2),
            y: CGFloat(frame.y + frame.height / 2)
        )
        unrotatedVertices[index] = ShapeGeometry.inverseRotated(
            worldPoint,
            around: oldCenter,
            cosine: cosine,
            sine: sine
        )
        guard let bounds = PointBounds(of: unrotatedVertices) else { return nil }

        let minimumExtent = CGFloat(ShapeElementBuilder.minimumFrameExtent)
        let width = max(bounds.width, minimumExtent)
        let height = max(bounds.height, minimumExtent)
        let midpoint = bounds.midpoint
        let tightOrigin = CGPoint(
            x: midpoint.x - width / 2,
            y: midpoint.y - height / 2
        )
        let newTightCenter = CGPoint(
            x: tightOrigin.x + width / 2,
            y: tightOrigin.y + height / 2
        )

        let centerDelta = CGPoint(
            x: newTightCenter.x - oldCenter.x,
            y: newTightCenter.y - oldCenter.y
        )
        let compensation = ShapeGeometry.rotationCompensation(
            forCenterDelta: centerDelta,
            cosine: cosine,
            sine: sine
        )
        let compensatedOrigin = CGPoint(
            x: tightOrigin.x + compensation.x,
            y: tightOrigin.y + compensation.y
        )
        let newFrame = CanvasRect(
            x: Double(compensatedOrigin.x),
            y: Double(compensatedOrigin.y),
            width: Double(width),
            height: Double(height)
        )

        // Translating both the tight frame and its unrotated geometry by the compensation keeps
        // normalized coordinates stable while moving the eventual rotation center.
        let horizontalCollapsed = bounds.width == 0
        let verticalCollapsed = bounds.height == 0
        let normalizedVertices = unrotatedVertices.map { vertex in
            let compensatedVertex = CGPoint(
                x: vertex.x + compensation.x,
                y: vertex.y + compensation.y
            )
            return CanvasPoint(
                x: horizontalCollapsed
                    ? 0.5
                    : Double((compensatedVertex.x - compensatedOrigin.x) / width),
                y: verticalCollapsed
                    ? 0.5
                    : Double((compensatedVertex.y - compensatedOrigin.y) / height)
            )
        }
        let updatedContent = ShapeContent(
            geometry: .polyline(
                vertices: normalizedVertices,
                isClosed: isClosed
            ),
            strokeColor: content.strokeColor,
            strokeWidth: content.strokeWidth
        )
        return (content: updatedContent, frame: newFrame)
    }
}
