import CoreGraphics
import Testing
@testable import VellumCore

@Suite("Shape ellipse editor")
struct ShapeEllipseEditorTests {
    private let frame = CanvasRect(x: 100, y: 60, width: 200, height: 120)
    private let accuracy: CGFloat = 0.0001

    @Test("Handles sit on the curve at the ends of each axis")
    func handlesSitOnTheCurve() {
        let handles = ShapeEllipseEditor.radiusHandles(frame: frame, rotation: 0)

        #expect(handles.count == 4)
        expectPoint(handles[0], equals: CGPoint(x: 200, y: 60))
        expectPoint(handles[1], equals: CGPoint(x: 300, y: 120))
        expectPoint(handles[2], equals: CGPoint(x: 200, y: 180))
        expectPoint(handles[3], equals: CGPoint(x: 100, y: 120))
    }

    @Test("Rotated handles follow the tilted curve")
    func rotatedHandlesFollowTheCurve() {
        let rotation = Double.pi / 6
        let handles = ShapeEllipseEditor.radiusHandles(frame: frame, rotation: rotation)
        let center = CGPoint(x: 200, y: 120)

        #expect(handles.count == 4)
        // Each handle keeps its distance from the center and gains the rotation angle.
        expectValue(distance(handles[0], center), equals: 60)
        expectValue(distance(handles[1], center), equals: 100)
        let topAngle = atan2(handles[0].y - center.y, handles[0].x - center.x)
        expectValue(topAngle, equals: -.pi / 2 + CGFloat(rotation))
    }

    @Test("Dragging one handle changes only that radius")
    func draggingAHandleChangesOneRadius() throws {
        let resized = try #require(
            ShapeEllipseEditor.resizing(
                handleIndex: 1,
                to: CGPoint(x: 360, y: 120),
                frame: frame,
                rotation: 0
            )
        )

        expectValue(CGFloat(resized.width), equals: 260)
        expectValue(CGFloat(resized.height), equals: 120)
        // The left edge — the opposite point on the curve — has not moved.
        expectValue(CGFloat(resized.x), equals: 100)
        expectValue(CGFloat(resized.y), equals: 60)
    }

    @Test("Dragging a handle on a rotated ellipse leaves the opposite point where it was")
    func rotatedDragKeepsTheOppositePointStill() throws {
        let rotation = Double.pi / 6
        let before = ShapeEllipseEditor.radiusHandles(frame: frame, rotation: rotation)
        let target = CGPoint(
            x: before[1].x + 40 * cos(CGFloat(rotation)),
            y: before[1].y + 40 * sin(CGFloat(rotation))
        )

        let resized = try #require(
            ShapeEllipseEditor.resizing(
                handleIndex: 1,
                to: target,
                frame: frame,
                rotation: rotation
            )
        )
        let after = ShapeEllipseEditor.radiusHandles(frame: resized, rotation: rotation)

        // The point opposite the one being dragged stays exactly where it was rendered, and the
        // dragged handle lands under the finger. The top and bottom handles do slide, because
        // they sit at the horizontal center, which has moved — but the radius they mark is
        // unchanged, so the ellipse grew along one axis only.
        expectPoint(after[3], equals: before[3])
        expectPoint(after[1], equals: target)
        expectValue(CGFloat(resized.height), equals: CGFloat(frame.height))
        expectValue(distance(after[0], after[2]), equals: distance(before[0], before[2]))
    }

    @Test("A handle cannot be dragged through the far side of the ellipse")
    func handleStopsAtTheMinimumExtent() throws {
        let resized = try #require(
            ShapeEllipseEditor.resizing(
                handleIndex: 1,
                to: CGPoint(x: 20, y: 120),
                frame: frame,
                rotation: 0
            )
        )

        expectValue(
            CGFloat(resized.width),
            equals: CGFloat(ShapeElementBuilder.minimumFrameExtent)
        )
        expectValue(CGFloat(resized.x), equals: 100)
    }

    @Test("An out-of-range handle index is rejected")
    func rejectsUnknownHandles() {
        #expect(
            ShapeEllipseEditor.resizing(
                handleIndex: 4,
                to: CGPoint(x: 200, y: 200),
                frame: frame,
                rotation: 0
            ) == nil
        )
    }

    private func expectPoint(
        _ actual: CGPoint,
        equals expected: CGPoint,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(distance(actual, expected) < accuracy, sourceLocation: sourceLocation)
    }

    private func expectValue(
        _ actual: CGFloat,
        equals expected: CGFloat,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual - expected) < accuracy, sourceLocation: sourceLocation)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
}
