import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class PageOrientationFlipTests: XCTestCase {
    func testPortraitToLandscapePreservesDrawingAndElementCoordinates() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let model = try await makeLoadedModel(rootDirectory: rootDirectory)
        let drawing = makeDrawing(
            from: CGPoint(x: 50, y: 80),
            to: CGPoint(x: 700, y: 500)
        )
        let element = makeElement(frame: CanvasRect(x: 120, y: 180, width: 260, height: 90))
        let canvasView = attachCanvas(to: model, drawing: drawing)
        model.canvasElements.hydrate([element])
        let drawingBefore = canvasView.drawing.dataRepresentation()
        let elementsBefore = model.canvasElements.elements

        XCTAssertTrue(model.setPageOrientation(.landscape))

        XCTAssertEqual(model.note?.pageOrientation, .landscape)
        XCTAssertEqual(canvasView.drawing.dataRepresentation(), drawingBefore)
        XCTAssertEqual(model.canvasElements.elements, elementsBefore)
        withExtendedLifetime(canvasView) {}
    }

    func testOrientationRoundTripIsAnExactInvolutionForContent() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let model = try await makeLoadedModel(rootDirectory: rootDirectory)
        let drawing = makeDrawing(
            from: CGPoint(x: 40, y: 40),
            to: CGPoint(x: 740, y: 940)
        )
        let element = makeElement(frame: CanvasRect(x: 300, y: 620, width: 180, height: 70))
        let canvasView = attachCanvas(to: model, drawing: drawing)
        model.canvasElements.hydrate([element])
        let originalDrawing = canvasView.drawing.dataRepresentation()
        let originalElements = model.canvasElements.elements

        XCTAssertTrue(model.setPageOrientation(.landscape))
        XCTAssertTrue(model.setPageOrientation(.portrait))

        XCTAssertEqual(model.note?.pageOrientation, .portrait)
        XCTAssertEqual(canvasView.drawing.dataRepresentation(), originalDrawing)
        XCTAssertEqual(model.canvasElements.elements, originalElements)
        withExtendedLifetime(canvasView) {}
    }

    func testLandscapeFlipAppendsPagesWithoutRekeyingTheDrawingAsset() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let model = try await makeLoadedModel(rootDirectory: rootDirectory)
        let drawing = makeDrawing(
            from: CGPoint(x: 100, y: 820),
            to: CGPoint(x: 200, y: 920)
        )
        let canvasView = attachCanvas(to: model, drawing: drawing)
        let originalPageCount = try XCTUnwrap(model.note?.pages.count)
        let originalDrawingAssetPath = try XCTUnwrap(model.note?.pages[0].drawingAssetPath)

        XCTAssertTrue(model.setPageOrientation(.landscape))

        XCTAssertGreaterThan(try XCTUnwrap(model.note?.pages.count), originalPageCount)
        XCTAssertEqual(model.note?.pages[0].drawingAssetPath, originalDrawingAssetPath)
        withExtendedLifetime(canvasView) {}
    }

    func testFlipIsRejectedDuringZoomSnapAndHiddenStrokeSelection() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let model = try await makeLoadedModel(rootDirectory: rootDirectory)
        let originalNote = try encodedNote(model)

        let zoomingCanvas = AlwaysZoomingCanvasView()
        attachCanvas(zoomingCanvas, to: model)
        XCTAssertFalse(model.setPageOrientation(.landscape))
        XCTAssertEqual(try encodedNote(model), originalNote)

        let snappingCanvas = PagedCanvasView(
            frame: CGRect(x: 0, y: 0, width: PageLayout.portraitContentWidth, height: 1_000)
        )
        snappingCanvas.contentWidthInContentSpace = PageLayout.portraitContentWidth
        snappingCanvas.layoutIfNeeded()
        snappingCanvas.zoomScale = 0.95
        snappingCanvas.handleZoomGestureEnded(atScale: snappingCanvas.zoomScale)
        XCTAssertTrue(snappingCanvas.isAnimatingZoomSnap)
        attachCanvas(snappingCanvas, to: model)
        XCTAssertFalse(model.setPageOrientation(.landscape))
        XCTAssertEqual(try encodedNote(model), originalNote)
        snappingCanvas.cancelZoomSnap()

        let selectionDrawing = makeDrawing(
            from: CGPoint(x: 20, y: 20),
            to: CGPoint(x: 140, y: 140)
        )
        snappingCanvas.drawing = selectionDrawing
        let selectionController = CanvasSelectionController()
        selectionController.canvasReference = model.canvasElements.canvasReference
        selectionController.elementsStore = model.canvasElements
        selectionController.beginCapture(at: CGPoint(x: 0, y: 0), mode: .boxed)
        selectionController.extendCapture(to: CGPoint(x: 200, y: 200))
        selectionController.endCapture()
        XCTAssertTrue(selectionController.beginMoveDrag())
        XCTAssertTrue(selectionController.hasHiddenStrokes)
        model.hasHiddenSelectionStrokes = { [weak selectionController] in
            selectionController?.hasHiddenStrokes ?? false
        }

        XCTAssertFalse(model.setPageOrientation(.landscape))
        XCTAssertEqual(try encodedNote(model), originalNote)

        selectionController.endMoveDrag()
        XCTAssertFalse(selectionController.hasHiddenStrokes)
        withExtendedLifetime((zoomingCanvas, snappingCanvas, selectionController)) {}
    }

    func testFlipIsRejectedForPDFBands() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let model = try await makeLoadedModel(rootDirectory: rootDirectory) { note in
            note.pages[0].background = .pdf
            note.pages[0].pdfPage = PDFPageReference(
                assetPath: "assets/source.pdf",
                pageIndex: 0
            )
        }
        let canvasView = attachCanvas(to: model)
        let originalNote = try encodedNote(model)

        XCTAssertFalse(model.setPageOrientation(.landscape))

        XCTAssertEqual(try encodedNote(model), originalNote)
        XCTAssertEqual(model.saveState, .saved)
        withExtendedLifetime(canvasView) {}
    }

    func testRejectedNoOpFlipDoesNotDirtyCleanNote() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let model = try await makeLoadedModel(rootDirectory: rootDirectory)
        let canvasView = attachCanvas(to: model)
        XCTAssertEqual(model.saveState, .saved)

        XCTAssertFalse(model.setPageOrientation(.portrait))

        XCTAssertEqual(model.note?.pageOrientation, .portrait)
        XCTAssertEqual(model.saveState, .saved)
        withExtendedLifetime(canvasView) {}
    }

    func testContentWidthQueryUsesDrawingAndElementsWithoutMutatingModel() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let model = try await makeLoadedModel(rootDirectory: rootDirectory)
        let fittingDrawing = makeDrawing(
            from: CGPoint(x: 30, y: 50),
            to: CGPoint(x: 300, y: 100)
        )
        let canvasView = attachCanvas(to: model, drawing: fittingDrawing)
        model.canvasElements.hydrate([
            makeElement(frame: CanvasRect(x: 400, y: 120, width: 200, height: 60)),
        ])
        let originalNote = try encodedNote(model)
        let originalSaveState = model.saveState

        XCTAssertFalse(model.orientationWouldPushContentOffPage(to: .portrait))

        model.canvasElements.hydrate([
            makeElement(frame: CanvasRect(x: 750, y: 120, width: 80, height: 60)),
        ])
        XCTAssertTrue(model.orientationWouldPushContentOffPage(to: .portrait))

        model.canvasElements.hydrate([])
        canvasView.drawing = makeDrawing(
            from: CGPoint(x: 760, y: 50),
            to: CGPoint(x: 840, y: 100)
        )
        XCTAssertTrue(model.orientationWouldPushContentOffPage(to: .portrait))

        XCTAssertEqual(try encodedNote(model), originalNote)
        XCTAssertEqual(model.saveState, originalSaveState)
        withExtendedLifetime(canvasView) {}
    }

    private func makeLoadedModel(
        rootDirectory: URL,
        configureNote: ((inout Note) -> Void)? = nil
    ) async throws -> NoteScreenModel {
        let container = AppContainer.live(rootDirectory: rootDirectory)
        var note = try await container.notes.createNote(title: "Orientation")
        if let configureNote {
            configureNote(&note)
            try await container.notes.saveNote(note)
        }
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()
        return model
    }

    @discardableResult
    private func attachCanvas(
        to model: NoteScreenModel,
        drawing: PKDrawing = PKDrawing()
    ) -> PagedCanvasView {
        let canvasView = PagedCanvasView()
        canvasView.drawing = drawing
        attachCanvas(canvasView, to: model)
        return canvasView
    }

    private func attachCanvas(_ canvasView: PKCanvasView, to model: NoteScreenModel) {
        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView
        model.canvasElements.canvasReference = canvasReference
        model.canvasElements.undoManagerOverride = UndoManager()
    }

    /// Encodes everything a rejected mutation must leave alone. `updatedAt` and
    /// `revision` are normalized out: the autosave path bumps both on its own
    /// schedule, so comparing them would assert on timing rather than on whether
    /// the rejection actually changed the note.
    private func encodedNote(_ model: NoteScreenModel) throws -> Data {
        var note = try XCTUnwrap(model.note)
        note.updatedAt = Date(timeIntervalSince1970: 0)
        note.revision = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(note)
    }

    private func makeElement(frame: CanvasRect) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Coordinates stay fixed",
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame,
            layerPlacement: .aboveInk
        )
    }

    private func makeDrawing(from start: CGPoint, to end: CGPoint) -> PKDrawing {
        let points = [
            PKStrokePoint(
                location: start,
                timeOffset: 0,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: end,
                timeOffset: 0.1,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
        ]
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
        return PKDrawing(strokes: [stroke])
    }
}

private final class AlwaysZoomingCanvasView: PKCanvasView {
    override var isZooming: Bool { true }
}
