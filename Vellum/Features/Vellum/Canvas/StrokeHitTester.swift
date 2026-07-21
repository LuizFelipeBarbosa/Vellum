import CoreGraphics
import Foundation
import PencilKit
import VellumCore

@MainActor
enum StrokeHitTester {
    static func strokeIndices(in drawing: PKDrawing, containedBy lasso: CGPath) -> IndexSet {
        let closedLassoPath = closedPath(copying: lasso)
        var indices = IndexSet()

        strokeLoop: for (index, stroke) in drawing.strokes.enumerated() {
            let visibleRanges = stroke.maskedPathRanges
            guard !visibleRanges.isEmpty else {
                // A fully erased stroke has no visible path ranges and cannot be selected.
                continue
            }

            for range in visibleRanges {
                for strokePoint in stroke.path.interpolatedPoints(
                    in: range,
                    by: .distance(6)
                ) {
                    let location = strokePoint.location.applying(stroke.transform)
                    if closedLassoPath.contains(location) {
                        indices.insert(index)
                        continue strokeLoop
                    }
                }
            }
        }

        return indices
    }

    static func strokeIndices(in drawing: PKDrawing, intersecting rect: CGRect) -> IndexSet {
        var indices = IndexSet()

        strokeLoop: for (index, stroke) in drawing.strokes.enumerated() {
            let visibleRanges = stroke.maskedPathRanges
            guard !visibleRanges.isEmpty else {
                // A fully erased stroke has no visible path ranges and cannot be selected.
                continue
            }

            for range in visibleRanges {
                for strokePoint in stroke.path.interpolatedPoints(
                    in: range,
                    by: .distance(6)
                ) {
                    let location = strokePoint.location.applying(stroke.transform)
                    if rect.contains(location) {
                        indices.insert(index)
                        continue strokeLoop
                    }
                }
            }
        }

        return indices
    }

    static func elementIDs(
        in elements: [CanvasElement],
        containedBy lasso: CGPath
    ) -> Set<UUID> {
        let closedLassoPath = closedPath(copying: lasso)
        var elementIDs = Set<UUID>()

        for element in elements {
            let rect = rect(for: element)
            // TODO: Account for element.rotation; v1 intentionally uses the axis-aligned frame.
            let testPoints = [
                CGPoint(x: rect.midX, y: rect.midY),
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY),
            ]

            if testPoints.contains(where: { closedLassoPath.contains($0) }) {
                elementIDs.insert(element.id)
            }
        }

        return elementIDs
    }

    static func elementIDs(
        in elements: [CanvasElement],
        intersecting rect: CGRect
    ) -> Set<UUID> {
        Set(
            elements.lazy
                .filter { rect.intersects(self.rect(for: $0)) }
                .map(\.id)
        )
    }

    private static func closedPath(copying path: CGPath) -> CGPath {
        let closedPath: CGMutablePath
        if let mutableCopy = path.mutableCopy() {
            closedPath = mutableCopy
        } else {
            closedPath = CGMutablePath()
            closedPath.addPath(path)
        }
        closedPath.closeSubpath()
        return closedPath
    }

    private static func rect(for element: CanvasElement) -> CGRect {
        CGRect(
            x: element.frame.x,
            y: element.frame.y,
            width: element.frame.width,
            height: element.frame.height
        )
    }
}
