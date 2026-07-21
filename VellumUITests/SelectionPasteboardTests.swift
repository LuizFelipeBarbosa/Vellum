import Foundation
import PencilKit
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class SelectionPasteboardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIPasteboard.general.items = []
    }

    override func tearDown() {
        UIPasteboard.general.items = []
        super.tearDown()
    }

    func testCopyPasteOffsetsFreshCopiesSelectsThemAndUndoesInOneStep() async throws {
        let element = makeElement(frame: CanvasRect(x: 60, y: 20, width: 30, height: 30))
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)]
                ),
            ],
            elements: [element]
        )
        selectMixedContent(in: harness)
        let originalStrokeCount = harness.canvasView.drawing.strokes.count
        let originalElements = harness.store.elements

        XCTAssertTrue(harness.controller.copySelection())
        await harness.controller.pasteFromPasteboard()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount + 1)
        XCTAssertEqual(harness.store.elements.count, originalElements.count + 1)
        let pastedElement = try XCTUnwrap(
            harness.store.elements.first(where: { $0.id != element.id })
        )
        XCTAssertNotEqual(pastedElement.id, element.id)
        XCTAssertEqual(pastedElement.frame.x, element.frame.x + 20, accuracy: 0.001)
        XCTAssertEqual(pastedElement.frame.y, element.frame.y + 20, accuracy: 0.001)
        XCTAssertEqual(
            harness.canvasView.drawing.strokes[1].transform.tx,
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            harness.canvasView.drawing.strokes[1].transform.ty,
            20,
            accuracy: 0.001
        )

        let selection = try XCTUnwrap(harness.controller.selection)
        XCTAssertEqual(selection.strokeIndices, IndexSet(integer: originalStrokeCount))
        XCTAssertEqual(selection.elementIDs, Set([pastedElement.id]))

        harness.undoManager.undo()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount)
        XCTAssertEqual(harness.store.elements, originalElements)
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "Paste must append strokes and elements in exactly one undo transaction"
        )
    }

    func testCutLeavesPayloadAndPasteRestoresOffsetEquivalentContent() async throws {
        let element = makeElement(frame: CanvasRect(x: 60, y: 20, width: 30, height: 30))
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)]
                ),
            ],
            elements: [element]
        )
        selectMixedContent(in: harness)

        harness.controller.cutSelection()

        XCTAssertTrue(harness.canvasView.drawing.strokes.isEmpty)
        XCTAssertTrue(harness.store.elements.isEmpty)
        XCTAssertNil(harness.controller.selection)
        XCTAssertTrue(SelectionPasteboard.hasPayload)
        XCTAssertTrue(harness.undoManager.canUndo)

        await harness.controller.pasteFromPasteboard()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        XCTAssertEqual(harness.store.elements.count, 1)
        let pastedElement = try XCTUnwrap(harness.store.elements.first)
        XCTAssertNotEqual(pastedElement.id, element.id)
        XCTAssertEqual(pastedElement.frame.x, element.frame.x + 20, accuracy: 0.001)
        XCTAssertEqual(pastedElement.frame.y, element.frame.y + 20, accuracy: 0.001)
        XCTAssertEqual(
            harness.canvasView.drawing.strokes[0].transform.tx,
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            harness.canvasView.drawing.strokes[0].transform.ty,
            20,
            accuracy: 0.001
        )
    }

    func testColdCacheCutDoesNotDeleteOrReplacePasteboard() {
        let element = makeImageElement(assetPath: "assets/cold.jpg")
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)]
                ),
            ],
            elements: [element]
        )
        selectMixedContent(in: harness)
        let originalStrokeCount = harness.canvasView.drawing.strokes.count
        let originalElementCount = harness.store.elements.count
        var failureMessage: String?
        harness.controller.onOperationFailed = { failureMessage = $0 }

        XCTAssertFalse(harness.controller.copySelection())
        harness.controller.cutSelection()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount)
        XCTAssertEqual(harness.store.elements.count, originalElementCount)
        XCTAssertFalse(SelectionPasteboard.hasPayload)
        XCTAssertTrue(UIPasteboard.general.items.isEmpty)
        XCTAssertFalse(failureMessage?.isEmpty ?? true)
    }

    func testWarmCacheCopyPreservesOriginalImageBytes() throws {
        let assetPath = "assets/original.png"
        let element = makeImageElement(assetPath: assetPath)
        let harness = makeHarness(strokes: [], elements: [element])
        let originalData = try XCTUnwrap(makePNGData())
        let image = try XCTUnwrap(UIImage(data: originalData))
        harness.store.cacheImage(image, data: originalData, forAssetPath: assetPath)
        selectMixedContent(in: harness)

        XCTAssertTrue(harness.controller.copySelection())

        let payload = try XCTUnwrap(SelectionPasteboard.read())
        XCTAssertEqual(payload.imageAssets[assetPath], originalData)
    }

    func testImagePastePersistsNewAssetPathAndWarmsImageCache() async throws {
        let originalAssetPath = "assets/original.jpg"
        let element = CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: originalAssetPath,
                    originalPixelSize: CanvasSize(width: 1, height: 1)
                )
            ),
            frame: CanvasRect(x: 40, y: 30, width: 50, height: 50)
        )
        let harness = makeHarness(strokes: [], elements: [element])
        let originalData = try XCTUnwrap(makePNGData())
        let image = try XCTUnwrap(UIImage(data: originalData))
        harness.store.cacheImage(
            image,
            data: originalData,
            forAssetPath: originalAssetPath
        )
        harness.controller.persistImageData = { _ in "assets/new.jpg" }
        harness.controller.beginCapture(at: CGPoint(x: 0, y: 0), mode: .boxed)
        harness.controller.extendCapture(to: CGPoint(x: 120, y: 120))
        harness.controller.endCapture()

        XCTAssertTrue(harness.controller.copySelection())
        await harness.controller.pasteFromPasteboard()

        let pasted = try XCTUnwrap(
            harness.store.elements.first(where: { $0.id != element.id })
        )
        guard case .image(let imageContent) = pasted.content else {
            return XCTFail("Expected the pasted element to remain an image")
        }
        XCTAssertEqual(imageContent.assetPath, "assets/new.jpg")
        XCTAssertNotNil(harness.store.imageCache["assets/new.jpg"])
        XCTAssertEqual(harness.store.imageDataCache["assets/new.jpg"], originalData)
    }

    private func selectMixedContent(in harness: Harness) {
        harness.controller.beginCapture(at: CGPoint(x: 0, y: 0), mode: .boxed)
        harness.controller.extendCapture(to: CGPoint(x: 110, y: 80))
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

    private func makeStroke(locations: [CGPoint]) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.1,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
    }

    private func makeElement(frame: CanvasRect) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Selected",
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame
        )
    }

    private func makeImageElement(
        assetPath: String,
        frame: CanvasRect = CanvasRect(x: 40, y: 30, width: 50, height: 50)
    ) -> CanvasElement {
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: assetPath,
                    originalPixelSize: CanvasSize(width: 2, height: 2)
                )
            ),
            frame: frame
        )
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
