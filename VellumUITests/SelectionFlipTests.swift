import Foundation
import PencilKit
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class SelectionFlipTests: XCTestCase {
    func testPKStrokeAcceptsNegativeDeterminantTransform() {
        let original = makeStroke(
            locations: [CGPoint(x: 20, y: 30), CGPoint(x: 40, y: 70)]
        )
        let pivot = CGPoint(x: 50, y: 50)
        let reflection = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(scaleX: -1, y: 1))
            .concatenating(
                CGAffineTransform(translationX: pivot.x, y: pivot.y)
            )
        let reflected = PKStroke(
            ink: original.ink,
            path: original.path,
            transform: original.transform.concatenating(reflection),
            mask: original.mask,
            randomSeed: original.randomSeed
        )

        let determinant =
            reflected.transform.a * reflected.transform.d
                - reflected.transform.b * reflected.transform.c
        XCTAssertLessThan(determinant, 0)
        XCTAssertEqual(
            reflected.renderBounds.midX,
            2 * pivot.x - original.renderBounds.midX,
            accuracy: 0.5
        )
    }

    func testFlipHorizontalReflectsSelectedStrokesAndPreservesBounds() throws {
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 45, y: 35)]
                ),
                makeStroke(
                    locations: [CGPoint(x: 70, y: 45), CGPoint(x: 95, y: 75)]
                ),
            ],
            elements: []
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 120, y: 100))
        let originalBounds = try XCTUnwrap(harness.controller.selectionBounds)
        let originalStrokeBounds = harness.canvasView.drawing.strokes
            .map(\.renderBounds)
            .reduce(CGRect.null) { $0.union($1) }
        let pivot = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        let expected = horizontalReflection(about: pivot)

        harness.controller.flipSelection(horizontal: true)

        for stroke in harness.canvasView.drawing.strokes {
            assertTransform(stroke.transform, equals: expected)
        }
        let reflectedStrokeBounds = harness.canvasView.drawing.strokes
            .map(\.renderBounds)
            .reduce(CGRect.null) { $0.union($1) }
        XCTAssertEqual(
            reflectedStrokeBounds.midX,
            originalStrokeBounds.midX,
            accuracy: 0.5
        )
        assertRect(reflectedStrokeBounds, equals: originalStrokeBounds, accuracy: 0.5)
        assertRect(
            try XCTUnwrap(harness.controller.selectionBounds),
            equals: originalBounds,
            accuracy: 0.5
        )
    }

    func testDoubleFlipRestoresStrokesAndElements() throws {
        let originalTransform = CGAffineTransform(translationX: 6, y: 4)
        let element = makeImageElement(
            frame: CanvasRect(x: 70, y: 20, width: 35, height: 42),
            rotation: 0.3,
            flippedHorizontally: true,
            flippedVertically: true
        )
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 15, y: 25), CGPoint(x: 45, y: 55)],
                    transform: originalTransform
                ),
            ],
            elements: [element]
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 130, y: 100))
        let originalBounds = try XCTUnwrap(harness.controller.selectionBounds)
        let originalElements = harness.store.elements

        harness.controller.flipSelection(horizontal: true)

        let onceFlipped = try XCTUnwrap(harness.store.elements.first)
        guard case .image(let onceFlippedImage) = onceFlipped.content else {
            return XCTFail("Expected the flipped element to remain an image")
        }
        XCTAssertFalse(onceFlippedImage.flippedHorizontally)
        XCTAssertTrue(onceFlippedImage.flippedVertically)

        harness.controller.flipSelection(horizontal: true)

        assertTransform(
            harness.canvasView.drawing.strokes[0].transform,
            equals: originalTransform
        )
        XCTAssertEqual(harness.store.elements, originalElements)
        assertRect(
            try XCTUnwrap(harness.controller.selectionBounds),
            equals: originalBounds,
            accuracy: 0.5
        )
    }

    func testFlipHorizontalReflectsMixedSelectionAsOneUnit() throws {
        let originalRotation = 0.37
        let element = makeImageElement(
            frame: CanvasRect(x: 85, y: 25, width: 35, height: 30),
            rotation: originalRotation
        )
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 10, y: 35), CGPoint(x: 35, y: 60)]
                ),
            ],
            elements: [element]
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 140, y: 100))
        let originalBounds = try XCTUnwrap(harness.controller.selectionBounds)
        let pivot = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        let originalCenterX = element.frame.x + element.frame.width / 2
        let originalCenterY = element.frame.y + element.frame.height / 2

        harness.controller.flipSelection(horizontal: true)

        let reflected = try XCTUnwrap(harness.store.elements.first)
        let reflectedCenterX = reflected.frame.x + reflected.frame.width / 2
        let reflectedCenterY = reflected.frame.y + reflected.frame.height / 2
        XCTAssertEqual(
            reflectedCenterX,
            2 * Double(pivot.x) - originalCenterX,
            accuracy: 0.000_001
        )
        XCTAssertEqual(reflectedCenterY, originalCenterY, accuracy: 0.000_001)
        XCTAssertEqual(reflected.rotation, -originalRotation, accuracy: 0.000_001)
        guard case .image(let reflectedImage) = reflected.content,
              case .image(let originalImage) = element.content else {
            return XCTFail("Expected an image element")
        }
        XCTAssertEqual(
            reflectedImage.flippedHorizontally,
            !originalImage.flippedHorizontally
        )
        XCTAssertEqual(
            reflectedImage.flippedVertically,
            originalImage.flippedVertically
        )
        assertRect(
            try XCTUnwrap(harness.controller.selectionBounds),
            equals: originalBounds,
            accuracy: 0.5
        )
    }

    func testFlipHorizontalRegistersOneUndoStepAndRestoresSelection() throws {
        let element = makeShapeElement(
            frame: CanvasRect(x: 65, y: 20, width: 32, height: 28),
            rotation: 0.2
        )
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 45, y: 45)]
                ),
            ],
            elements: [element]
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 120, y: 90))
        let originalElements = harness.store.elements
        XCTAssertFalse(harness.undoManager.canUndo)

        harness.controller.flipSelection(horizontal: true)

        XCTAssertTrue(harness.undoManager.canUndo)
        XCTAssertEqual(harness.undoManager.undoActionName, "Flip Horizontal")
        let flippedElement = try XCTUnwrap(harness.store.elements.first)
        guard case .shape(let flippedShape) = flippedElement.content,
              case .polyline(let vertices, let isClosed) = flippedShape.geometry else {
            return XCTFail("Expected a polyline shape")
        }
        XCTAssertEqual(
            vertices,
            [
                CanvasPoint(x: 1, y: 0),
                CanvasPoint(x: 0, y: 1),
            ]
        )
        XCTAssertFalse(isClosed)

        harness.undoManager.undo()

        // PencilKit serialization is not byte-stable across decode/encode, so assert the
        // restored drawing semantically: one stroke, back on an identity transform (a
        // surviving flip would leave a mirrored transform with determinant -1).
        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        let restoredTransform = try XCTUnwrap(harness.canvasView.drawing.strokes.first).transform
        XCTAssertEqual(restoredTransform.a, 1, accuracy: 0.001)
        XCTAssertEqual(restoredTransform.b, 0, accuracy: 0.001)
        XCTAssertEqual(restoredTransform.c, 0, accuracy: 0.001)
        XCTAssertEqual(restoredTransform.d, 1, accuracy: 0.001)
        XCTAssertEqual(restoredTransform.tx, 0, accuracy: 0.001)
        XCTAssertEqual(restoredTransform.ty, 0, accuracy: 0.001)
        XCTAssertEqual(harness.store.elements, originalElements)
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "A mixed flip must register exactly one undo entry"
        )
        XCTAssertTrue(harness.undoManager.canRedo)

        harness.undoManager.redo()

        XCTAssertTrue(harness.undoManager.canUndo)
        let redoneElement = try XCTUnwrap(harness.store.elements.first)
        guard case .shape(let redoneShape) = redoneElement.content,
              case .polyline(let vertices, let isClosed) = redoneShape.geometry else {
            return XCTFail("Expected a polyline shape")
        }
        XCTAssertEqual(
            vertices,
            [
                CanvasPoint(x: 1, y: 0),
                CanvasPoint(x: 0, y: 1),
            ]
        )
        XCTAssertFalse(isClosed)
    }

    func testFlipSelectionSurvivesDrawingDataRoundTrip() throws {
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 45, y: 35)]
                ),
            ],
            elements: []
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 80, y: 60))

        harness.controller.flipSelection(horizontal: true)

        // Mirrored PencilKit transforms must survive drawing serialization for save/reload.
        let flippedDrawing = harness.canvasView.drawing
        let decodedDrawing = try PKDrawing(data: flippedDrawing.dataRepresentation())
        XCTAssertEqual(decodedDrawing.strokes.count, flippedDrawing.strokes.count)
        for (decodedStroke, flippedStroke) in zip(
            decodedDrawing.strokes,
            flippedDrawing.strokes
        ) {
            assertRect(
                decodedStroke.renderBounds,
                equals: flippedStroke.renderBounds,
                accuracy: 0.5
            )
            let determinant =
                decodedStroke.transform.a * decodedStroke.transform.d
                    - decodedStroke.transform.b * decodedStroke.transform.c
            XCTAssertLessThan(determinant, 0)
        }
    }

    func testDuplicateAndCopyPastePreserveImageFlipState() async throws {
        UIPasteboard.general.items = []
        defer { UIPasteboard.general.items = [] }

        let assetPath = "assets/original.png"
        let element = makeImageElement(
            assetPath: assetPath,
            frame: CanvasRect(x: 40, y: 30, width: 50, height: 40),
            rotation: 0.28,
            flippedVertically: true
        )
        let harness = makeHarness(strokes: [], elements: [element])
        let imageData = try XCTUnwrap(makePNGData())
        let image = try XCTUnwrap(UIImage(data: imageData))
        harness.store.cacheImage(image, data: imageData, forAssetPath: assetPath)
        harness.controller.persistImageData = { _ in "assets/pasted.png" }
        harness.controller.selectElement(id: element.id)

        harness.controller.flipSelection(horizontal: true)

        let flippedSource = try XCTUnwrap(harness.store.elements.first)
        guard case .image(let flippedSourceImage) = flippedSource.content else {
            return XCTFail("Expected the flipped source to remain an image")
        }
        XCTAssertEqual(flippedSource.frame, element.frame)
        XCTAssertEqual(flippedSource.rotation, -element.rotation)
        XCTAssertTrue(flippedSourceImage.flippedHorizontally)
        XCTAssertTrue(flippedSourceImage.flippedVertically)
        assertRect(
            try XCTUnwrap(harness.controller.selectionBounds),
            equals: CGRect(
                x: element.frame.x,
                y: element.frame.y,
                width: element.frame.width,
                height: element.frame.height
            )
        )

        harness.controller.duplicateSelection()

        let duplicateID = try XCTUnwrap(harness.controller.selection?.elementIDs.first)
        let duplicate = try XCTUnwrap(
            harness.store.elements.first(where: { $0.id == duplicateID })
        )
        guard case .image(let duplicateImage) = duplicate.content else {
            return XCTFail("Expected the duplicate to remain an image")
        }
        XCTAssertEqual(
            duplicateImage.flippedHorizontally,
            flippedSourceImage.flippedHorizontally
        )
        XCTAssertEqual(
            duplicateImage.flippedVertically,
            flippedSourceImage.flippedVertically
        )
        XCTAssertEqual(duplicate.rotation, flippedSource.rotation)

        XCTAssertTrue(harness.controller.copySelection())
        await harness.controller.pasteFromPasteboard()

        let pastedID = try XCTUnwrap(harness.controller.selection?.elementIDs.first)
        let pasted = try XCTUnwrap(
            harness.store.elements.first(where: { $0.id == pastedID })
        )
        guard case .image(let pastedImage) = pasted.content else {
            return XCTFail("Expected the pasted element to remain an image")
        }
        XCTAssertEqual(
            pastedImage.flippedHorizontally,
            duplicateImage.flippedHorizontally
        )
        XCTAssertEqual(
            pastedImage.flippedVertically,
            duplicateImage.flippedVertically
        )
        XCTAssertEqual(pasted.rotation, duplicate.rotation)
    }

    func testFlipSelectionNoOpsWithoutSelectionAndDuringHandleDrag() throws {
        let element = makeElement(
            frame: CanvasRect(x: 65, y: 20, width: 32, height: 28),
            rotation: 0.2
        )
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 45, y: 45)]
                ),
            ],
            elements: [element]
        )
        let originalDrawingData = harness.canvasView.drawing.dataRepresentation()
        let originalElements = harness.store.elements

        harness.controller.flipSelection(horizontal: true)

        XCTAssertNil(harness.controller.selection)
        XCTAssertNil(harness.controller.selectionBounds)
        XCTAssertEqual(
            harness.canvasView.drawing.dataRepresentation(),
            originalDrawingData
        )
        XCTAssertEqual(harness.store.elements, originalElements)
        XCTAssertFalse(harness.undoManager.canUndo)

        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 120, y: 90))
        let selection = try XCTUnwrap(harness.controller.selection)
        let selectedBounds = try XCTUnwrap(harness.controller.selectionBounds)
        harness.controller.beginHandleDrag()
        XCTAssertTrue(harness.controller.isHandleDragging)
        let hiddenDrawingData = harness.canvasView.drawing.dataRepresentation()

        harness.controller.flipSelection(horizontal: true)

        XCTAssertEqual(
            harness.canvasView.drawing.dataRepresentation(),
            hiddenDrawingData
        )
        XCTAssertEqual(harness.store.elements, originalElements)
        XCTAssertEqual(
            harness.controller.selection?.strokeIndices,
            selection.strokeIndices
        )
        XCTAssertEqual(
            harness.controller.selection?.elementIDs,
            selection.elementIDs
        )
        assertRect(
            try XCTUnwrap(harness.controller.selectionBounds),
            equals: selectedBounds
        )
        XCTAssertFalse(harness.undoManager.canUndo)

        harness.controller.endHandleDrag()

        XCTAssertEqual(
            harness.canvasView.drawing.dataRepresentation(),
            originalDrawingData
        )
        XCTAssertEqual(harness.store.elements, originalElements)
        XCTAssertFalse(harness.undoManager.canUndo)
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

    private func makeShapeElement(
        frame: CanvasRect,
        rotation: Double = 0,
        strokeWidth: Double = 6
    ) -> CanvasElement {
        CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0),
                            CanvasPoint(x: 1, y: 1),
                        ],
                        isClosed: false
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: strokeWidth
                )
            ),
            frame: frame,
            rotation: rotation
        )
    }

    private func makeImageElement(
        assetPath: String = "assets/selected.png",
        frame: CanvasRect,
        rotation: Double = 0,
        flippedHorizontally: Bool = false,
        flippedVertically: Bool = false
    ) -> CanvasElement {
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: assetPath,
                    originalPixelSize: CanvasSize(width: 2, height: 2),
                    flippedHorizontally: flippedHorizontally,
                    flippedVertically: flippedVertically
                )
            ),
            frame: frame,
            rotation: rotation
        )
    }

    private func horizontalReflection(about pivot: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(scaleX: -1, y: 1))
            .concatenating(
                CGAffineTransform(translationX: pivot.x, y: pivot.y)
            )
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

    private func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    private func makePNGData() -> Data? {
        Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nH0AAAAASUVORK5CYII="
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
