import CoreGraphics
import Foundation
@testable import Vellum
import VellumCore
import XCTest

final class ElementReordererTests: XCTestCase {
    func testToFrontMovesBelowInkSelectionAfterEveryAboveInkElement() throws {
        let frame = CanvasRect(x: 20, y: 20, width: 80, height: 60)
        let selected = makeImage(frame: frame, placement: .belowInk)
        let firstAbove = makeText(frame: frame, placement: .aboveInk)
        let secondAbove = makeShape(frame: frame, placement: .aboveInk)

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [selected, firstAbove, secondAbove],
                selectedIDs: [selected.id],
                direction: .toFront,
                inkRects: []
            )
        )

        XCTAssertEqual(result.map(\.id), [firstAbove.id, secondAbove.id, selected.id])
        XCTAssertEqual(result.last?.layerPlacement, .aboveInk)
    }

    func testToFrontPromotesTopmostBelowInkElementAboveInk() throws {
        let selected = makeImage(
            frame: CanvasRect(x: 20, y: 20, width: 80, height: 60),
            placement: .belowInk
        )

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [selected],
                selectedIDs: [selected.id],
                direction: .toFront,
                inkRects: [CGRect(x: 40, y: 40, width: 10, height: 10)]
            )
        )

        XCTAssertEqual(result.map(\.id), [selected.id])
        XCTAssertEqual(result.first?.layerPlacement, .aboveInk)
    }

    func testToFrontReturnsNilForTopmostBelowInkElementWithoutOverlappingInk() {
        let selected = makeImage(
            frame: CanvasRect(x: 20, y: 20, width: 80, height: 60),
            placement: .belowInk
        )

        XCTAssertNil(
            ElementReorderer.reorder(
                elements: [selected],
                selectedIDs: [selected.id],
                direction: .toFront,
                inkRects: [CGRect(x: 300, y: 300, width: 10, height: 10)]
            )
        )
    }

    func testToBackDemotesBottommostAboveInkElementBelowInk() throws {
        let selected = makeText(
            frame: CanvasRect(x: 20, y: 20, width: 80, height: 60),
            placement: .aboveInk
        )

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [selected],
                selectedIDs: [selected.id],
                direction: .toBack,
                inkRects: [CGRect(x: 40, y: 40, width: 10, height: 10)]
            )
        )

        XCTAssertEqual(result.map(\.id), [selected.id])
        XCTAssertEqual(result.first?.layerPlacement, .belowInk)
    }

    func testToBackAtBottomEdgeOnlyDemotesWhenInkOverlapsSelection() throws {
        let selected = makeText(
            frame: CanvasRect(x: 20, y: 20, width: 80, height: 60),
            placement: .aboveInk
        )

        XCTAssertNil(
            ElementReorderer.reorder(
                elements: [selected],
                selectedIDs: [selected.id],
                direction: .toBack,
                inkRects: [CGRect(x: 300, y: 300, width: 10, height: 10)]
            )
        )

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [selected],
                selectedIDs: [selected.id],
                direction: .toBack,
                inkRects: [CGRect(x: 40, y: 40, width: 10, height: 10)]
            )
        )

        XCTAssertEqual(result.map(\.id), [selected.id])
        XCTAssertEqual(result.first?.layerPlacement, .belowInk)
    }

    func testForwardHopsInkOnlyWhenInkOverlapsSelection() throws {
        let selected = makeImage(
            frame: CanvasRect(x: 20, y: 20, width: 80, height: 60),
            placement: .belowInk
        )
        let lower = makeImage(
            frame: CanvasRect(x: 300, y: 300, width: 40, height: 40),
            placement: .belowInk
        )
        let above = makeText(
            frame: CanvasRect(x: 400, y: 400, width: 40, height: 40),
            placement: .aboveInk
        )
        let elements = [lower, selected, above]

        XCTAssertNil(
            ElementReorderer.reorder(
                elements: elements,
                selectedIDs: [selected.id],
                direction: .forward,
                inkRects: []
            )
        )

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: elements,
                selectedIDs: [selected.id],
                direction: .forward,
                inkRects: [CGRect(x: 40, y: 40, width: 10, height: 10)]
            )
        )

        XCTAssertEqual(result.map(\.id), [lower.id, selected.id, above.id])
        XCTAssertEqual(
            result.first(where: { $0.id == selected.id })?.layerPlacement,
            .aboveInk
        )
    }

    func testForwardSkipsNonOverlappingElementBeforeNearestCandidate() throws {
        let selected = makeImage(
            frame: CanvasRect(x: 20, y: 20, width: 80, height: 60),
            placement: .belowInk
        )
        let farAway = makeShape(
            frame: CanvasRect(x: 300, y: 300, width: 40, height: 40),
            placement: .belowInk
        )
        let candidate = makeShape(
            frame: CanvasRect(x: 60, y: 40, width: 80, height: 60),
            placement: .belowInk
        )

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [selected, farAway, candidate],
                selectedIDs: [selected.id],
                direction: .forward,
                inkRects: []
            )
        )

        XCTAssertEqual(result.map(\.id), [farAway.id, candidate.id, selected.id])
        XCTAssertEqual(result.last?.layerPlacement, .belowInk)
    }

    func testForwardMovesNoncontiguousBelowInkSelectionPastInterleavedCandidate() throws {
        let frame = CanvasRect(x: 20, y: 20, width: 80, height: 60)
        let firstSelected = makeImage(frame: frame, placement: .belowInk)
        let candidate = makeShape(frame: frame, placement: .belowInk)
        let secondSelected = makeText(frame: frame, placement: .belowInk)

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [firstSelected, candidate, secondSelected],
                selectedIDs: [firstSelected.id, secondSelected.id],
                direction: .forward,
                inkRects: []
            )
        )

        XCTAssertEqual(
            result.map(\.id),
            [candidate.id, firstSelected.id, secondSelected.id]
        )
        XCTAssertTrue(result.allSatisfy { $0.layerPlacement == .belowInk })
    }

    func testBackwardHopsInkOnlyWhenInkOverlapsSelection() throws {
        let below = makeImage(
            frame: CanvasRect(x: 300, y: 300, width: 40, height: 40),
            placement: .belowInk
        )
        let selected = makeText(
            frame: CanvasRect(x: 20, y: 20, width: 80, height: 60),
            placement: .aboveInk
        )
        let higher = makeText(
            frame: CanvasRect(x: 400, y: 400, width: 40, height: 40),
            placement: .aboveInk
        )
        let elements = [below, selected, higher]

        XCTAssertNil(
            ElementReorderer.reorder(
                elements: elements,
                selectedIDs: [selected.id],
                direction: .backward,
                inkRects: []
            )
        )

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: elements,
                selectedIDs: [selected.id],
                direction: .backward,
                inkRects: [CGRect(x: 40, y: 40, width: 10, height: 10)]
            )
        )

        XCTAssertEqual(result.map(\.id), [below.id, selected.id, higher.id])
        XCTAssertEqual(
            result.first(where: { $0.id == selected.id })?.layerPlacement,
            .belowInk
        )
    }

    func testBackwardSkipsNonOverlappingElementBeforeNearestCandidate() throws {
        let candidate = makeText(
            frame: CanvasRect(x: 60, y: 40, width: 80, height: 60),
            placement: .aboveInk
        )
        let farAway = makeText(
            frame: CanvasRect(x: 300, y: 300, width: 40, height: 40),
            placement: .aboveInk
        )
        let selected = makeText(
            frame: CanvasRect(x: 20, y: 20, width: 80, height: 60),
            placement: .aboveInk
        )

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [candidate, farAway, selected],
                selectedIDs: [selected.id],
                direction: .backward,
                inkRects: []
            )
        )

        XCTAssertEqual(result.map(\.id), [selected.id, candidate.id, farAway.id])
        XCTAssertEqual(result.first?.layerPlacement, .aboveInk)
    }

    func testBackwardMovesNoncontiguousBelowInkSelectionBehindInterleavedCandidate() throws {
        let frame = CanvasRect(x: 20, y: 20, width: 80, height: 60)
        let firstSelected = makeImage(frame: frame, placement: .belowInk)
        let candidate = makeShape(frame: frame, placement: .belowInk)
        let secondSelected = makeText(frame: frame, placement: .belowInk)

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [firstSelected, candidate, secondSelected],
                selectedIDs: [firstSelected.id, secondSelected.id],
                direction: .backward,
                inkRects: []
            )
        )

        XCTAssertEqual(
            result.map(\.id),
            [firstSelected.id, secondSelected.id, candidate.id]
        )
        XCTAssertTrue(result.allSatisfy { $0.layerPlacement == .belowInk })
    }

    func testBackwardStageTwoMovesSelectionBeforeOverlappingBelowInkCandidate() throws {
        let candidate = makeImage(
            frame: CanvasRect(x: 60, y: 40, width: 80, height: 60),
            placement: .belowInk
        )
        let farAway = makeText(
            frame: CanvasRect(x: 300, y: 300, width: 40, height: 40),
            placement: .aboveInk
        )
        let selected = makeText(
            frame: CanvasRect(x: 20, y: 20, width: 80, height: 60),
            placement: .aboveInk
        )

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [candidate, farAway, selected],
                selectedIDs: [selected.id],
                direction: .backward,
                inkRects: []
            )
        )

        XCTAssertEqual(result.map(\.id), [selected.id, candidate.id, farAway.id])
        XCTAssertEqual(result.first?.layerPlacement, .belowInk)
    }

    func testMultiSelectionPreservesMixedBlockOrderAndAdoptsOnePlacement() throws {
        let frame = CanvasRect(x: 20, y: 20, width: 80, height: 60)
        let bottom = makeImage(
            frame: CanvasRect(x: 300, y: 300, width: 40, height: 40),
            placement: .belowInk
        )
        let selectedImage = makeImage(frame: frame, placement: .belowInk)
        let selectedShape = makeShape(frame: frame, placement: .belowInk)
        let candidate = makeText(frame: frame, placement: .aboveInk)
        let top = makeText(
            frame: CanvasRect(x: 400, y: 400, width: 40, height: 40),
            placement: .aboveInk
        )

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [bottom, selectedImage, selectedShape, candidate, top],
                selectedIDs: [selectedImage.id, selectedShape.id],
                direction: .forward,
                inkRects: []
            )
        )

        XCTAssertEqual(
            result.map(\.id),
            [bottom.id, candidate.id, selectedImage.id, selectedShape.id, top.id]
        )
        let movedPlacements = result
            .filter { [selectedImage.id, selectedShape.id].contains($0.id) }
            .map(\.layerPlacement)
        XCTAssertEqual(movedPlacements, [.aboveInk, .aboveInk])
    }

    func testSuccessfulReorderMaterializesEveryPlacement() throws {
        let frame = CanvasRect(x: 20, y: 20, width: 80, height: 60)
        let selected = makeImage(frame: frame)
        let candidate = makeShape(frame: frame, placement: .belowInk)
        let text = makeText(frame: frame)

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [selected, candidate, text],
                selectedIDs: [selected.id],
                direction: .forward,
                inkRects: []
            )
        )

        XCTAssertTrue(result.allSatisfy { $0.layerPlacement != nil })
    }

    func testLegacyInputIsNormalizedBeforeReorderMaterializesIt() throws {
        let frame = CanvasRect(x: 20, y: 20, width: 80, height: 60)
        let firstText = makeText(frame: frame)
        let selectedShape = makeShape(frame: frame)
        let firstImage = makeImage(frame: frame)
        let secondText = makeText(frame: frame)
        let secondImage = makeImage(frame: frame)

        let result = try XCTUnwrap(
            ElementReorderer.reorder(
                elements: [
                    firstText,
                    selectedShape,
                    firstImage,
                    secondText,
                    secondImage,
                ],
                selectedIDs: [selectedShape.id],
                direction: .toFront,
                inkRects: []
            )
        )

        XCTAssertEqual(
            result.filter { $0.id != selectedShape.id }.map(\.id),
            [firstImage.id, secondImage.id, firstText.id, secondText.id]
        )
        XCTAssertTrue(result.allSatisfy { $0.layerPlacement != nil })
    }

    func testToFrontAndToBackReturnNilAtTheirRespectiveEdges() {
        let frame = CanvasRect(x: 20, y: 20, width: 80, height: 60)
        let back = makeImage(frame: frame, placement: .belowInk)
        let front = makeText(frame: frame, placement: .aboveInk)
        let elements = [back, front]

        XCTAssertNil(
            ElementReorderer.reorder(
                elements: elements,
                selectedIDs: [front.id],
                direction: .toFront,
                inkRects: []
            )
        )
        XCTAssertNil(
            ElementReorderer.reorder(
                elements: elements,
                selectedIDs: [back.id],
                direction: .toBack,
                inkRects: []
            )
        )
    }

    private func makeImage(
        frame: CanvasRect,
        placement: LayerPlacement? = nil
    ) -> CanvasElement {
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: "assets/test.jpg",
                    originalPixelSize: CanvasSize(width: 800, height: 600)
                )
            ),
            frame: frame,
            layerPlacement: placement
        )
    }

    private func makeShape(
        frame: CanvasRect,
        placement: LayerPlacement? = nil
    ) -> CanvasElement {
        CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0.5),
                            CanvasPoint(x: 1, y: 0.5),
                        ],
                        isClosed: false
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 4
                )
            ),
            frame: frame,
            layerPlacement: placement
        )
    }

    private func makeText(
        frame: CanvasRect,
        placement: LayerPlacement? = nil
    ) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Text",
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame,
            layerPlacement: placement
        )
    }
}
