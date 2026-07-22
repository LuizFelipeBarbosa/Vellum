import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

@Suite("CanvasElement rotated bounding boxes")
struct CanvasElementRotatedBoundingBoxTests {
    @Test("Zero rotation preserves the original frame exactly")
    func zeroRotationPreservesFrame() {
        let frame = CanvasRect(x: 12, y: 34, width: 180, height: 72)
        let element = makeElement(frame: frame, rotation: 0)
        let expected = CGRect(x: 12, y: 34, width: 180, height: 72)

        #expect(element.rotatedBoundingBox == expected)
    }

    @Test("A quarter turn swaps a non-square frame's dimensions around its center")
    func quarterTurnSwapsDimensions() {
        let element = makeElement(
            frame: CanvasRect(x: 20, y: 40, width: 240, height: 80),
            rotation: .pi / 2
        )
        let bounds = element.rotatedBoundingBox

        #expect(abs(bounds.midX - 140) < 0.0001)
        #expect(abs(bounds.midY - 80) < 0.0001)
        #expect(abs(bounds.width - 80) < 0.0001)
        #expect(abs(bounds.height - 240) < 0.0001)
    }

    @Test("A 45-degree square grows to side times square root of two around its center")
    func diagonalSquareBoundingBox() {
        let side: CGFloat = 100
        let element = makeElement(
            frame: CanvasRect(x: 30, y: 50, width: Double(side), height: Double(side)),
            rotation: .pi / 4
        )
        let bounds = element.rotatedBoundingBox
        let expectedSide = side * sqrt(2)

        #expect(abs(bounds.midX - 80) < 0.0001)
        #expect(abs(bounds.midY - 100) < 0.0001)
        #expect(abs(bounds.width - expectedSide) < 0.0001)
        #expect(abs(bounds.height - expectedSide) < 0.0001)
    }

    private func makeElement(frame: CanvasRect, rotation: Double) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Bounds",
                    fontSize: 16,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame,
            rotation: rotation
        )
    }
}
