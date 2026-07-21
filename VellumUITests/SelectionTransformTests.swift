import Foundation
import PencilKit
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class SelectionTransformTests: XCTestCase {
    func testScaleTwoXKeepsSelectionCenterInvariant() throws {
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 50, y: 40)]
                ),
            ],
            elements: []
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        let originalBounds = try XCTUnwrap(harness.controller.selectionBounds)

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 2, height: 2),
            rotation: 0
        )
        harness.controller.endHandleDrag()

        let transformedBounds = harness.canvasView.drawing.strokes[0].renderBounds
        XCTAssertEqual(transformedBounds.midX, originalBounds.midX, accuracy: 0.5)
        XCTAssertEqual(transformedBounds.midY, originalBounds.midY, accuracy: 0.5)

        let selectionBounds = try XCTUnwrap(harness.controller.selectionBounds)
        // renderBounds pads by ink width, which does not scale linearly with the
        // geometry transform — allow a few points around the doubled size.
        XCTAssertEqual(selectionBounds.width, originalBounds.width * 2, accuracy: 3)
        XCTAssertEqual(selectionBounds.height, originalBounds.height * 2, accuracy: 3)
    }

    func testRotationNinetyDegreesUsesVerifiedCompositeOrder() throws {
        let originalRotation = 0.25
        let element = makeElement(
            frame: CanvasRect(x: 70, y: 25, width: 30, height: 24),
            rotation: originalRotation
        )
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 45, y: 45)]
                ),
            ],
            elements: [element]
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 130, y: 90))
        let bounds = try XCTUnwrap(harness.controller.selectionBounds)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 1, height: 1),
            rotation: .pi / 2
        )
        harness.controller.endHandleDrag()

        let transformedElement = try XCTUnwrap(harness.store.elements.first)
        XCTAssertEqual(
            transformedElement.rotation,
            originalRotation + .pi / 2,
            accuracy: 0.000_001
        )

        // Independently mirrors the verified row-vector application order:
        // p * T(-c) * S * R * T(c), which maps c back to c.
        let expected = CGAffineTransform(
            translationX: -center.x,
            y: -center.y
        )
        .concatenating(CGAffineTransform(scaleX: 1, y: 1))
        .concatenating(CGAffineTransform(rotationAngle: .pi / 2))
        .concatenating(
            CGAffineTransform(translationX: center.x, y: center.y)
        )
        let actual = harness.canvasView.drawing.strokes[0].transform
        assertTransform(actual, equals: expected)
    }

    func testMixedHandleTransformIsExactlyOneUndoStep() throws {
        let element = makeElement(
            frame: CanvasRect(x: 65, y: 20, width: 32, height: 28),
            rotation: 0.2
        )
        let stroke = makeStroke(
            locations: [CGPoint(x: 20, y: 20), CGPoint(x: 45, y: 45)]
        )
        let harness = makeHarness(strokes: [stroke], elements: [element])
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 130, y: 90))

        let originalTransform = harness.canvasView.drawing.strokes[0].transform
        let originalElement = try XCTUnwrap(harness.store.elements.first)

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 1.5, height: 0.8),
            rotation: .pi / 4
        )
        harness.controller.endHandleDrag()

        XCTAssertTrue(harness.undoManager.canUndo)
        XCTAssertNotEqual(harness.canvasView.drawing.strokes[0].transform, originalTransform)
        XCTAssertNotEqual(harness.store.elements.first, originalElement)

        harness.undoManager.undo()

        assertTransform(
            harness.canvasView.drawing.strokes[0].transform,
            equals: originalTransform
        )
        XCTAssertEqual(harness.store.elements, [originalElement])
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "A mixed transform must register one undo entry for drawing and elements"
        )
    }

    func testRestyleColorChangesOnlySelectedStrokeAndSurvivesDrawingRoundTrip() throws {
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 50, y: 40)],
                    color: .black
                ),
                makeStroke(
                    locations: [CGPoint(x: 250, y: 250), CGPoint(x: 280, y: 280)],
                    color: .blue
                ),
            ],
            elements: []
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        let color = CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)

        harness.controller.restyleSelection(color: color, strokeWidth: nil)

        assertColor(harness.canvasView.drawing.strokes[0].ink.color, equals: color)
        assertUIColor(harness.canvasView.drawing.strokes[1].ink.color, equals: .blue)

        let data = PKDrawing(
            strokes: harness.canvasView.drawing.strokes
        ).dataRepresentation()
        let roundTripped = try PKDrawing(data: data)
        assertColor(roundTripped.strokes[0].ink.color, equals: color)
        assertUIColor(roundTripped.strokes[1].ink.color, equals: .blue)
    }

    func testRestyleWidthPreservesPointCountTransformAndCreationDate() throws {
        let creationDate = Date(timeIntervalSince1970: 1_234_567)
        let originalTransform = CGAffineTransform(translationX: 7, y: 9)
            .concatenating(CGAffineTransform(rotationAngle: 0.15))
        let stroke = makeStroke(
            locations: [
                CGPoint(x: 20, y: 20),
                CGPoint(x: 35, y: 30),
                CGPoint(x: 50, y: 45),
            ],
            size: CGSize(width: 4, height: 6),
            transform: originalTransform,
            creationDate: creationDate
        )
        let harness = makeHarness(strokes: [stroke], elements: [])
        select(in: harness, from: CGPoint(x: -20, y: -20), to: CGPoint(x: 140, y: 140))
        let targetWidth = 13.0

        harness.controller.restyleSelection(color: nil, strokeWidth: targetWidth)

        let restyled = harness.canvasView.drawing.strokes[0]
        XCTAssertEqual(restyled.path.count, stroke.path.count)
        XCTAssertEqual(averageTipWidth(restyled), targetWidth, accuracy: 0.001)
        assertTransform(restyled.transform, equals: stroke.transform)
        XCTAssertEqual(restyled.path.creationDate, stroke.path.creationDate)
    }

    private func select(
        in harness: Harness,
        from start: CGPoint,
        to end: CGPoint
    ) {
        harness.controller.beginCapture(at: start, mode: .boxed)
        harness.controller.extendCapture(to: end)
        harness.controller.endCapture()
    }

    private func makeHarness(strokes: [PKStroke], elements: [CanvasElement]) -> Harness {
        let canvasView = PKCanvasView()
        canvasView.drawing = PKDrawing(strokes: strokes)

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

    private func makeStroke(
        locations: [CGPoint],
        color: UIColor = .black,
        size: CGSize = CGSize(width: 4, height: 4),
        transform: CGAffineTransform = .identity,
        creationDate: Date = Date()
    ) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.1,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: color),
            path: PKStrokePath(controlPoints: points, creationDate: creationDate),
            transform: transform
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

    private func averageTipWidth(_ stroke: PKStroke) -> Double {
        let total = stroke.path.reduce(CGFloat.zero) { $0 + $1.size.width }
        return Double(total / CGFloat(stroke.path.count))
    }

    private func assertTransform(
        _ actual: CGAffineTransform,
        equals expected: CGAffineTransform,
        accuracy: CGFloat = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.a, expected.a, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.c, expected.c, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.d, expected.d, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.tx, expected.tx, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.ty, expected.ty, accuracy: accuracy, file: file, line: line)
    }

    private func assertColor(
        _ actual: UIColor,
        equals expected: CodableColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(
            actual.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            file: file,
            line: line
        )
        XCTAssertEqual(red, CGFloat(expected.red), accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(green, CGFloat(expected.green), accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(blue, CGFloat(expected.blue), accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(alpha, CGFloat(expected.alpha), accuracy: 0.01, file: file, line: line)
    }

    private func assertUIColor(
        _ actual: UIColor,
        equals expected: UIColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualComponents = actual.cgColor.components ?? []
        let expectedComponents = expected.cgColor.components ?? []
        XCTAssertEqual(actualComponents.count, expectedComponents.count, file: file, line: line)
        for (actual, expected) in zip(actualComponents, expectedComponents) {
            XCTAssertEqual(actual, expected, accuracy: 0.01, file: file, line: line)
        }
    }

    private struct Harness {
        let canvasView: PKCanvasView
        let canvasReference: NoteCanvasReference
        let store: CanvasElementsStore
        let undoManager: UndoManager
        let controller: CanvasSelectionController
    }
}
