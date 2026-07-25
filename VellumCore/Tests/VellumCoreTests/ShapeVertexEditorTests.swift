import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

@Suite("Shape vertex editor")
struct ShapeVertexEditorTests {
    private let color = CodableColor(red: 0.1, green: 0.2, blue: 0.3)
    private let accuracy: CGFloat = 0.0001

    @Test("Builder storage round-trips polygon and line vertices")
    func builderStorageRoundTripsPolylineVertices() {
        let shapes: [RecognizedShape] = [
            .polyline(
                vertices: [
                    CGPoint(x: 20, y: 35),
                    CGPoint(x: 120, y: 20),
                    CGPoint(x: 155, y: 95),
                    CGPoint(x: 45, y: 125),
                ],
                isClosed: true
            ),
            .polyline(
                vertices: [
                    CGPoint(x: 75, y: 20),
                    CGPoint(x: 75, y: 150),
                ],
                isClosed: false
            ),
        ]

        for shape in shapes {
            let built = ShapeElementBuilder.element(
                from: shape,
                strokeColor: color,
                strokeWidth: 3
            )
            let actual = ShapeVertexEditor.absoluteVertices(
                content: built.content,
                frame: built.frame,
                rotation: built.rotation
            )
            guard case .polyline(let expected, _) = shape else { continue }

            expectVertices(actual, equal: expected)
        }
    }

    @Test("Moving a vertex without rotation preserves every other vertex")
    func movingVertexWithoutRotationPreservesOtherVertices() throws {
        let built = ShapeElementBuilder.element(
            from: .polyline(
                vertices: [
                    CGPoint(x: 20, y: 30),
                    CGPoint(x: 100, y: 20),
                    CGPoint(x: 130, y: 100),
                ],
                isClosed: true
            ),
            strokeColor: color,
            strokeWidth: 2
        )
        let before = ShapeVertexEditor.absoluteVertices(
            content: built.content,
            frame: built.frame,
            rotation: 0
        )
        let target = CGPoint(x: -15, y: 145)
        let moved = try #require(
            ShapeVertexEditor.movingVertex(
                at: 1,
                to: target,
                content: built.content,
                frame: built.frame,
                rotation: 0
            )
        )
        let after = ShapeVertexEditor.absoluteVertices(
            content: moved.content,
            frame: moved.frame,
            rotation: 0
        )

        #expect(distance(after[1], target) < accuracy)
        #expect(distance(after[0], before[0]) < accuracy)
        #expect(distance(after[2], before[2]) < accuracy)
        expectFrameIsTight(moved.frame, around: after)
    }

    @Test("Rotation compensation fixes unmoved vertices in world space")
    func rotationCompensationPreservesOtherWorldVertices() throws {
        let built = ShapeElementBuilder.element(
            from: .polyline(
                vertices: [
                    CGPoint(x: 25, y: 35),
                    CGPoint(x: 115, y: 20),
                    CGPoint(x: 150, y: 105),
                    CGPoint(x: 45, y: 130),
                ],
                isClosed: true
            ),
            strokeColor: color,
            strokeWidth: 2
        )
        let rotation = Double.pi / 6
        let before = ShapeVertexEditor.absoluteVertices(
            content: built.content,
            frame: built.frame,
            rotation: rotation
        )
        let target = CGPoint(x: 185, y: 80)
        let moved = try #require(
            ShapeVertexEditor.movingVertex(
                at: 2,
                to: target,
                content: built.content,
                frame: built.frame,
                rotation: rotation
            )
        )
        let after = ShapeVertexEditor.absoluteVertices(
            content: moved.content,
            frame: moved.frame,
            rotation: rotation
        )

        #expect(distance(after[2], target) < accuracy)
        for index in before.indices where index != 2 {
            // This is the load-bearing frame-center compensation invariant.
            #expect(distance(after[index], before[index]) < accuracy)
        }
    }

    @Test("Collapsed line axes inflate and remain stable on a subsequent move")
    func collapsedLineAxisInflatesAndRemainsStable() throws {
        let built = ShapeElementBuilder.element(
            from: .polyline(
                vertices: [
                    CGPoint(x: 20, y: 20),
                    CGPoint(x: 80, y: 80),
                ],
                isClosed: false
            ),
            strokeColor: color,
            strokeWidth: 2
        )
        let vertical = try #require(
            ShapeVertexEditor.movingVertex(
                at: 0,
                to: CGPoint(x: 80, y: 10),
                content: built.content,
                frame: built.frame,
                rotation: 0
            )
        )
        let verticalVertices = ShapeVertexEditor.absoluteVertices(
            content: vertical.content,
            frame: vertical.frame,
            rotation: 0
        )

        #expect(abs(vertical.frame.width - ShapeElementBuilder.minimumFrameExtent) < 0.0001)
        #expect(distance(verticalVertices[0], CGPoint(x: 80, y: 10)) < accuracy)
        #expect(distance(verticalVertices[1], CGPoint(x: 80, y: 80)) < accuracy)

        let movedAgain = try #require(
            ShapeVertexEditor.movingVertex(
                at: 1,
                to: CGPoint(x: 95, y: 90),
                content: vertical.content,
                frame: vertical.frame,
                rotation: 0
            )
        )
        let finalVertices = ShapeVertexEditor.absoluteVertices(
            content: movedAgain.content,
            frame: movedAgain.frame,
            rotation: 0
        )

        #expect(finalVertices.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect([
            movedAgain.frame.x,
            movedAgain.frame.y,
            movedAgain.frame.width,
            movedAgain.frame.height,
        ].allSatisfy { $0.isFinite })
        #expect(distance(finalVertices[0], verticalVertices[0]) < accuracy)
        #expect(distance(finalVertices[1], CGPoint(x: 95, y: 90)) < accuracy)
    }

    @Test("Invalid indices and ellipse content cannot move a vertex")
    func invalidMovesReturnNil() {
        let polyline = ShapeElementBuilder.element(
            from: .polyline(
                vertices: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50)],
                isClosed: false
            ),
            strokeColor: color,
            strokeWidth: 2
        )
        let ellipse = ShapeElementBuilder.element(
            from: .ellipse(
                center: CGPoint(x: 50, y: 50),
                radiusX: 30,
                radiusY: 20,
                rotation: .pi / 6
            ),
            strokeColor: color,
            strokeWidth: 2
        )

        #expect(
            ShapeVertexEditor.movingVertex(
                at: -1,
                to: .zero,
                content: polyline.content,
                frame: polyline.frame,
                rotation: 0
            ) == nil
        )
        #expect(
            ShapeVertexEditor.movingVertex(
                at: 2,
                to: .zero,
                content: polyline.content,
                frame: polyline.frame,
                rotation: 0
            ) == nil
        )
        #expect(
            ShapeVertexEditor.movingVertex(
                at: 0,
                to: .zero,
                content: ellipse.content,
                frame: ellipse.frame,
                rotation: ellipse.rotation
            ) == nil
        )
        #expect(
            ShapeVertexEditor.absoluteVertices(
                content: ellipse.content,
                frame: ellipse.frame,
                rotation: ellipse.rotation
            ).isEmpty
        )
    }

    private func expectVertices(_ actual: [CGPoint], equal expected: [CGPoint]) {
        #expect(actual.count == expected.count)
        guard actual.count == expected.count else { return }
        for (actualVertex, expectedVertex) in zip(actual, expected) {
            #expect(distance(actualVertex, expectedVertex) < accuracy)
        }
    }

    private func expectFrameIsTight(_ frame: CanvasRect, around vertices: [CGPoint]) {
        guard let first = vertices.first else { return }
        let minimumX = vertices.dropFirst().reduce(first.x) { min($0, $1.x) }
        let maximumX = vertices.dropFirst().reduce(first.x) { max($0, $1.x) }
        let minimumY = vertices.dropFirst().reduce(first.y) { min($0, $1.y) }
        let maximumY = vertices.dropFirst().reduce(first.y) { max($0, $1.y) }
        let expectedWidth = max(
            maximumX - minimumX,
            CGFloat(ShapeElementBuilder.minimumFrameExtent)
        )
        let expectedHeight = max(
            maximumY - minimumY,
            CGFloat(ShapeElementBuilder.minimumFrameExtent)
        )
        let expectedMidX = (minimumX + maximumX) / 2
        let expectedMidY = (minimumY + maximumY) / 2

        #expect(abs(CGFloat(frame.width) - expectedWidth) < accuracy)
        #expect(abs(CGFloat(frame.height) - expectedHeight) < accuracy)
        #expect(abs(CGFloat(frame.x + frame.width / 2) - expectedMidX) < accuracy)
        #expect(abs(CGFloat(frame.y + frame.height / 2) - expectedMidY) < accuracy)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }
}
