import Foundation
import PencilKit
import UIKit
@testable import Vellum
import VellumCore
import UniformTypeIdentifiers
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
        // This no-argument paste also guards the legacy nil-target +20/+20 offset.
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

    func testPasteAtTargetCentersPayloadBounds() async throws {
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
        let target = CGPoint(x: 320, y: 280)

        XCTAssertTrue(harness.controller.copySelection())
        await harness.controller.pasteFromPasteboard(at: target)

        let pastedSelection = try XCTUnwrap(harness.controller.selection)
        var pastedBounds: CGRect?
        for index in pastedSelection.strokeIndices
        where harness.canvasView.drawing.strokes.indices.contains(index) {
            let renderBounds = harness.canvasView.drawing.strokes[index].renderBounds
            pastedBounds = pastedBounds.map { $0.union(renderBounds) } ?? renderBounds
        }
        for element in harness.store.elements
        where pastedSelection.elementIDs.contains(element.id) {
            let frame = CGRect(
                x: element.frame.x,
                y: element.frame.y,
                width: element.frame.width,
                height: element.frame.height
            ).standardized
            pastedBounds = pastedBounds.map { $0.union(frame) } ?? frame
        }

        let bounds = try XCTUnwrap(pastedBounds)
        XCTAssertEqual(bounds.midX, target.x, accuracy: 1)
        XCTAssertEqual(bounds.midY, target.y, accuracy: 1)
    }

    func testPasteAtTargetClampsToPageEdges() async throws {
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

        XCTAssertTrue(harness.controller.copySelection())
        await harness.controller.pasteFromPasteboard(at: CGPoint(x: 1, y: 1))

        let pastedSelection = try XCTUnwrap(harness.controller.selection)
        var pastedBounds: CGRect?
        for index in pastedSelection.strokeIndices
        where harness.canvasView.drawing.strokes.indices.contains(index) {
            let renderBounds = harness.canvasView.drawing.strokes[index].renderBounds
            pastedBounds = pastedBounds.map { $0.union(renderBounds) } ?? renderBounds
        }
        for element in harness.store.elements
        where pastedSelection.elementIDs.contains(element.id) {
            let frame = CGRect(
                x: element.frame.x,
                y: element.frame.y,
                width: element.frame.width,
                height: element.frame.height
            ).standardized
            pastedBounds = pastedBounds.map { $0.union(frame) } ?? frame
        }

        let bounds = try XCTUnwrap(pastedBounds)
        XCTAssertGreaterThanOrEqual(bounds.minX, -0.001)
        XCTAssertLessThanOrEqual(bounds.maxX, PageLayout.portraitContentWidth + 0.001)
        XCTAssertGreaterThanOrEqual(bounds.minY, -0.001)
    }

    func testPasteAtTargetIsOneUndoTransaction() async {
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
        await harness.controller.pasteFromPasteboard(at: CGPoint(x: 320, y: 280))

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount + 1)
        XCTAssertEqual(harness.store.elements.count, originalElements.count + 1)

        harness.undoManager.undo()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount)
        XCTAssertEqual(harness.store.elements, originalElements)
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "Targeted paste must append strokes and elements in exactly one undo transaction"
        )
    }

    func testHasSystemImageWithoutPayloadEnablesCanPaste() throws {
        let harness = makeHarness(strokes: [], elements: [])
        let imageData = try XCTUnwrap(makePNGData())
        UIPasteboard.general.setData(
            imageData,
            forPasteboardType: UTType.png.identifier
        )

        XCTAssertTrue(SelectionPasteboard.hasSystemImage)
        XCTAssertFalse(SelectionPasteboard.hasPayload)
        XCTAssertTrue(harness.controller.canPaste)
    }

    func testReadSystemImageDataReturnsExactBytesForRawDataType() async throws {
        let imageData = try XCTUnwrap(makePNGData())
        UIPasteboard.general.setData(
            imageData,
            forPasteboardType: UTType.png.identifier
        )

        let readData = await SelectionPasteboard.readSystemImageData()
        XCTAssertEqual(readData, imageData)
    }

    func testReadSystemImageDataLoadsPromisedImageProvider() async {
        let promisedData = Data("promised image data".utf8)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.image.identifier,
            visibility: .all
        ) { completion in
            completion(promisedData, nil)
            return nil
        }
        UIPasteboard.general.itemProviders = [provider]

        let readData = await SelectionPasteboard.readSystemImageData()
        XCTAssertEqual(readData, promisedData)
    }

    func testPasteFromPasteboardFallsBackToSystemImageAndSelectsResult() async throws {
        let harness = makeHarness(strokes: [], elements: [])
        let imageData = try XCTUnwrap(makePNGData())
        UIPasteboard.general.setData(
            imageData,
            forPasteboardType: UTType.png.identifier
        )
        var receivedData: Data?
        var receivedTarget: CGPoint?
        let importedID = UUID()
        harness.controller.importSystemImage = { data, target in
            receivedData = data
            receivedTarget = target
            return importedID
        }
        harness.store.hydrate([
            CanvasElement(
                id: importedID,
                content: .text(
                    TextBoxContent(
                        text: "placeholder",
                        fontSize: 18,
                        color: CodableColor(red: 0, green: 0, blue: 0)
                    )
                ),
                frame: CanvasRect(x: 0, y: 0, width: 10, height: 10)
            ),
        ])
        let target = CGPoint(x: 150, y: 220)

        await harness.controller.pasteFromPasteboard(at: target)

        XCTAssertEqual(receivedData, imageData)
        XCTAssertEqual(receivedTarget, target)
        XCTAssertEqual(harness.controller.selection?.elementIDs, Set([importedID]))
    }

    func testTargetedPasteReportsClaimedUnreadableContent() async {
        let harness = makeHarness(strokes: [], elements: [])
        UIPasteboard.general.setData(
            Data("not a Vellum payload".utf8),
            forPasteboardType: SelectionPasteboard.pasteboardType
        )
        var failureMessage: String?
        harness.controller.onOperationFailed = { failureMessage = $0 }

        await harness.controller.pasteFromPasteboard(at: CGPoint(x: 150, y: 220))

        XCTAssertEqual(failureMessage, "Couldn't read the copied content.")
    }

    func testUntargetedPasteDoesNotReportClaimedUnreadableContent() async {
        let harness = makeHarness(strokes: [], elements: [])
        UIPasteboard.general.setData(
            Data("not a Vellum payload".utf8),
            forPasteboardType: SelectionPasteboard.pasteboardType
        )
        var failureMessage: String?
        harness.controller.onOperationFailed = { failureMessage = $0 }

        await harness.controller.pasteFromPasteboard()

        XCTAssertNil(failureMessage)
    }

    func testTargetedPasteDoesNotReportEmptyPasteboard() async {
        let harness = makeHarness(strokes: [], elements: [])
        var failureMessage: String?
        harness.controller.onOperationFailed = { failureMessage = $0 }

        await harness.controller.pasteFromPasteboard(at: CGPoint(x: 150, y: 220))

        XCTAssertNil(failureMessage)
    }

    func testPasteFromPasteboardPrefersVellumPayloadOverSystemImage() async throws {
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
        XCTAssertTrue(harness.controller.copySelection())

        let imageData = try XCTUnwrap(makePNGData())
        var pasteboardItems = UIPasteboard.general.items
        pasteboardItems[0][UTType.png.identifier] = imageData
        UIPasteboard.general.items = pasteboardItems
        XCTAssertTrue(SelectionPasteboard.hasPayload)
        XCTAssertTrue(SelectionPasteboard.hasSystemImage)

        var systemImageCalled = false
        harness.controller.importSystemImage = { _, _ in
            systemImageCalled = true
            return nil
        }

        await harness.controller.pasteFromPasteboard()

        XCTAssertFalse(systemImageCalled)
        XCTAssertEqual(harness.store.elements.count, 2)
    }

    func testRequestPasteAffordanceLifecycle() async {
        let element = makeElement(frame: CanvasRect(x: 60, y: 20, width: 30, height: 30))
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)]
                ),
            ],
            elements: [element]
        )
        let firstTarget = CGPoint(x: 120, y: 140)
        let secondTarget = CGPoint(x: 180, y: 220)

        harness.controller.requestPasteAffordance(at: firstTarget)
        XCTAssertNil(harness.controller.pendingPasteTarget)

        selectMixedContent(in: harness)
        XCTAssertTrue(harness.controller.copySelection())
        harness.controller.requestPasteAffordance(at: firstTarget)
        XCTAssertEqual(harness.controller.pendingPasteTarget, firstTarget)
        harness.controller.requestPasteAffordance(at: secondTarget)
        XCTAssertEqual(harness.controller.pendingPasteTarget, secondTarget)

        harness.controller.clearSelection()
        XCTAssertNil(harness.controller.pendingPasteTarget)

        harness.controller.selectElement(id: element.id)
        harness.controller.requestPasteAffordance(at: firstTarget)
        harness.controller.toolChanged()
        XCTAssertNil(harness.controller.pendingPasteTarget)
        XCTAssertNil(harness.controller.selection)

        harness.controller.selectElement(id: element.id, survivesNextToolChange: true)
        harness.controller.requestPasteAffordance(at: firstTarget)
        harness.controller.toolChanged()
        XCTAssertNil(harness.controller.pendingPasteTarget)
        XCTAssertNotNil(harness.controller.selection)

        harness.controller.requestPasteAffordance(at: firstTarget)
        harness.controller.beginCapture(at: CGPoint(x: 0, y: 0), mode: .boxed)
        XCTAssertNil(harness.controller.pendingPasteTarget)

        harness.controller.requestPasteAffordance(at: firstTarget)
        harness.controller.selectElement(id: element.id)
        XCTAssertNil(harness.controller.pendingPasteTarget)

        harness.controller.requestPasteAffordance(at: firstTarget)
        await harness.controller.pasteFromPasteboard(at: secondTarget)
        XCTAssertNil(harness.controller.pendingPasteTarget)
    }

    func testPasteBubblePositionCentersAboveMiddleTap() {
        let viewportSize = CGSize(width: 400, height: 300)
        let tap = CGPoint(x: 200, y: 150)

        let position = SelectionPasteBubbleView.position(
            forTapAt: tap,
            in: viewportSize
        )

        XCTAssertEqual(position.x, tap.x, accuracy: 0.001)
        XCTAssertEqual(
            position.y,
            tap.y - 12 - SelectionPasteBubbleView.bubbleSize.height / 2,
            accuracy: 0.001
        )
    }

    func testPasteBubblePositionClampsNearTopLeft() {
        let viewportSize = CGSize(width: 400, height: 300)
        let margin: CGFloat = 8

        let position = SelectionPasteBubbleView.position(
            forTapAt: CGPoint(x: 1, y: 1),
            in: viewportSize
        )

        XCTAssertEqual(
            position.x,
            SelectionPasteBubbleView.bubbleSize.width / 2 + margin,
            accuracy: 0.001
        )
        XCTAssertEqual(
            position.y,
            SelectionPasteBubbleView.bubbleSize.height / 2 + margin,
            accuracy: 0.001
        )
    }

    func testPasteBubblePositionClampsNearBottomRight() {
        let viewportSize = CGSize(width: 400, height: 300)
        let margin: CGFloat = 8

        let position = SelectionPasteBubbleView.position(
            forTapAt: CGPoint(
                x: viewportSize.width + 20,
                y: viewportSize.height + 20
            ),
            in: viewportSize
        )

        XCTAssertEqual(
            position.x,
            viewportSize.width - SelectionPasteBubbleView.bubbleSize.width / 2 - margin,
            accuracy: 0.001
        )
        XCTAssertEqual(
            position.y,
            viewportSize.height - SelectionPasteBubbleView.bubbleSize.height / 2 - margin,
            accuracy: 0.001
        )
    }

    func testCopyPastePreservesLayerPlacement() async throws {
        var element = makeElement(
            frame: CanvasRect(x: 60, y: 20, width: 30, height: 30)
        )
        element.layerPlacement = .aboveInk
        let harness = makeHarness(strokes: [], elements: [element])
        harness.controller.selectElement(id: element.id)

        XCTAssertTrue(harness.controller.copySelection())
        await harness.controller.pasteFromPasteboard()

        let pasted = try XCTUnwrap(
            harness.store.elements.first(where: { $0.id != element.id })
        )
        XCTAssertEqual(pasted.layerPlacement, .aboveInk)
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
