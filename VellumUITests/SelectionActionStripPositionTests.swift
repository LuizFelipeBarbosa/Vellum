import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class SelectionActionStripPositionTests: XCTestCase {
    func testPositionPrefersAboveWhenBothPlacementsFit() {
        let avoidRect = CGRect(x: 200, y: 200, width: 100, height: 80)
        let stripSize = CGSize(width: 120, height: 40)
        let viewportSize = CGSize(width: 600, height: 600)

        let position = SelectionActionStripView.position(
            avoiding: avoidRect,
            stripSize: stripSize,
            in: viewportSize
        )
        let stripFrame = frame(centeredAt: position, size: stripSize)

        XCTAssertEqual(position.y, avoidRect.minY - 12 - stripSize.height / 2, accuracy: 0.001)
        XCTAssertEqual(stripFrame.maxY, avoidRect.minY - 12, accuracy: 0.001)
        XCTAssertFalse(stripFrame.intersects(avoidRect))
    }

    func testPositionFallsBelowNearViewportTop() {
        let avoidRect = CGRect(x: 200, y: 20, width: 100, height: 80)
        let stripSize = CGSize(width: 120, height: 40)
        let viewportSize = CGSize(width: 600, height: 600)

        let position = SelectionActionStripView.position(
            avoiding: avoidRect,
            stripSize: stripSize,
            in: viewportSize
        )
        let stripFrame = frame(centeredAt: position, size: stripSize)

        XCTAssertGreaterThanOrEqual(stripFrame.minY, avoidRect.maxY)
        XCTAssertFalse(stripFrame.intersects(avoidRect))
    }

    func testPositionPinsInsideViewportBottomWhenNeitherPlacementFits() {
        let avoidRect = CGRect(x: 100, y: 0, width: 300, height: 600)
        let stripSize = CGSize(width: 120, height: 40)
        let viewportSize = CGSize(width: 600, height: 600)

        let position = SelectionActionStripView.position(
            avoiding: avoidRect,
            stripSize: stripSize,
            in: viewportSize
        )
        let stripFrame = frame(centeredAt: position, size: stripSize)

        XCTAssertLessThanOrEqual(stripFrame.maxY, viewportSize.height - 8)
        XCTAssertEqual(
            position.y,
            viewportSize.height - 8 - stripSize.height / 2,
            accuracy: 0.001
        )
    }

    func testPositionClampsHorizontallyAndCentersInTinyViewport() {
        let stripSize = CGSize(width: 120, height: 40)
        let viewportSize = CGSize(width: 600, height: 600)

        let leftPosition = SelectionActionStripView.position(
            avoiding: CGRect(x: -20, y: 200, width: 10, height: 40),
            stripSize: stripSize,
            in: viewportSize
        )
        XCTAssertGreaterThanOrEqual(
            frame(centeredAt: leftPosition, size: stripSize).minX,
            8
        )

        let rightPosition = SelectionActionStripView.position(
            avoiding: CGRect(x: 610, y: 200, width: 10, height: 40),
            stripSize: stripSize,
            in: viewportSize
        )
        XCTAssertLessThanOrEqual(
            frame(centeredAt: rightPosition, size: stripSize).maxX,
            viewportSize.width - 8
        )

        let tinyViewportSize = CGSize(width: 100, height: 50)
        let tinyPosition = SelectionActionStripView.position(
            avoiding: CGRect(x: 20, y: 10, width: 60, height: 30),
            stripSize: stripSize,
            in: tinyViewportSize
        )
        XCTAssertEqual(tinyPosition.x, tinyViewportSize.width / 2, accuracy: 0.001)
        XCTAssertEqual(tinyPosition.y, tinyViewportSize.height / 2, accuracy: 0.001)
    }

    func testNonPinnedPlacementsNeverIntersectAvoidanceRectAcrossViewport() {
        let viewportSize = CGSize(width: 500, height: 400)
        let stripSize = CGSize(width: 120, height: 40)
        let originsX: [CGFloat] = [0, 20, 190, 380, 460]
        let originsY: [CGFloat] = [0, 20, 100, 260, 360]
        let sizes = [
            CGSize(width: 40, height: 40),
            CGSize(width: 120, height: 100),
        ]

        for originX in originsX {
            for originY in originsY {
                for size in sizes {
                    let avoidRect = CGRect(
                        x: originX,
                        y: originY,
                        width: size.width,
                        height: size.height
                    )
                    let aboveFits = avoidRect.minY - 12 - stripSize.height >= 8
                    let belowFits =
                        avoidRect.maxY + 12 + stripSize.height <= viewportSize.height - 8
                    guard aboveFits || belowFits else { continue }

                    let position = SelectionActionStripView.position(
                        avoiding: avoidRect,
                        stripSize: stripSize,
                        in: viewportSize
                    )
                    let stripFrame = frame(centeredAt: position, size: stripSize)

                    XCTAssertFalse(
                        stripFrame.intersects(avoidRect),
                        "Strip \(stripFrame) intersects avoidance rect \(avoidRect)"
                    )
                }
            }
        }
    }

    func testUnrotatedSelectionAvoidsResizeAndRotationHandleChrome() throws {
        let element = makeElement(
            frame: CanvasRect(x: 100, y: 200, width: 120, height: 60)
        )
        let harness = makeHarness(elements: [element])
        harness.controller.selectElement(id: element.id)

        let selectionBounds = try XCTUnwrap(harness.controller.selectionBounds)
        let avoidanceBounds = try XCTUnwrap(harness.controller.stripAvoidanceBounds)
        let expected = selectionBounds.insetBy(dx: -14, dy: -14).union(CGRect(
            x: selectionBounds.midX - 16,
            y: selectionBounds.minY - 44,
            width: 32,
            height: 44
        ))

        assertEqual(avoidanceBounds, expected)
    }

    func testRotatedSelectionAvoidsPaintedBoundingBox() throws {
        let element = makeElement(
            frame: CanvasRect(x: 100, y: 200, width: 200, height: 50),
            rotation: .pi / 4
        )
        let harness = makeHarness(elements: [element])
        harness.controller.selectElement(id: element.id)

        let selectionBounds = try XCTUnwrap(harness.controller.selectionBounds)
        let avoidanceBounds = try XCTUnwrap(harness.controller.stripAvoidanceBounds)
        let handleBounds = selectionBounds.insetBy(dx: -14, dy: -14).union(CGRect(
            x: selectionBounds.midX - 16,
            y: selectionBounds.minY - 44,
            width: 32,
            height: 44
        ))
        let expected = handleBounds.union(element.rotatedBoundingBox)

        assertEqual(avoidanceBounds, expected)
        XCTAssertGreaterThan(avoidanceBounds.height, handleBounds.height)
    }

    func testNoSelectionHasNoStripAvoidanceBounds() {
        let harness = makeHarness(elements: [])

        XCTAssertNil(harness.controller.stripAvoidanceBounds)
    }

    private func frame(centeredAt point: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func assertEqual(
        _ actual: CGRect,
        _ expected: CGRect,
        accuracy: CGFloat = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    private func makeHarness(elements: [CanvasElement]) -> Harness {
        let canvasView = PKCanvasView()
        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView

        let undoManager = UndoManager()
        let store = CanvasElementsStore()
        store.canvasReference = canvasReference
        store.undoManagerOverride = undoManager
        store.hydrate(elements)

        let controller = CanvasSelectionController()
        controller.canvasReference = canvasReference
        controller.elementsStore = store
        undoManager.removeAllActions()

        return Harness(
            canvasView: canvasView,
            canvasReference: canvasReference,
            store: store,
            undoManager: undoManager,
            controller: controller
        )
    }

    private func makeElement(frame: CanvasRect, rotation: Double = 0) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Selected",
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame,
            rotation: rotation
        )
    }

    private struct Harness {
        let canvasView: PKCanvasView
        let canvasReference: NoteCanvasReference
        let store: CanvasElementsStore
        let undoManager: UndoManager
        let controller: CanvasSelectionController
    }
}
