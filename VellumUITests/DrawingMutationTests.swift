import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class DrawingMutationTests: XCTestCase {
    func testTransactionMutatesDrawingOnceAndUndoRestoresItOnce() {
        var drawingChanges: [Data] = []
        var externalChangeCount = 0
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { drawingChanges.append($0) },
            onViewportChanged: nil
        )
        coordinator.onExternalDrawingChange = { externalChangeCount += 1 }

        let canvasView = PKCanvasView()
        canvasView.delegate = coordinator
        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView
        let undoManager = UndoManager()
        let store = CanvasElementsStore()
        store.canvasReference = canvasReference
        store.undoManagerOverride = undoManager

        store.performTransaction("Add Stroke") {
            store.mutateDrawing { drawing in
                drawing.strokes.append(makeStroke())
            }
        }

        XCTAssertEqual(drawingChanges.count, 1)
        XCTAssertEqual(externalChangeCount, 0)
        XCTAssertEqual(canvasView.drawing.strokes.count, 1)

        undoManager.undo()

        XCTAssertTrue(canvasView.drawing.strokes.isEmpty)
        XCTAssertEqual(drawingChanges.count, 2)
        XCTAssertEqual(externalChangeCount, 0)
    }

    func testUserDrawingChangeNotifiesAutosaveAndExternalObservers() {
        var drawingChanges: [Data] = []
        var externalChangeCount = 0
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { drawingChanges.append($0) },
            onViewportChanged: nil
        )
        coordinator.onExternalDrawingChange = { externalChangeCount += 1 }

        let canvasView = PKCanvasView()
        canvasView.delegate = coordinator
        // Assigning .drawing on a live PKCanvasView invokes the delegate synchronously.
        canvasView.drawing = PKDrawing(strokes: [makeStroke()])

        XCTAssertEqual(drawingChanges.count, 1)
        XCTAssertEqual(externalChangeCount, 1)
    }

    func testNoOpTransactionDoesNotNotifyOrRegisterUndo() {
        var drawingChanges: [Data] = []
        var externalChangeCount = 0
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { drawingChanges.append($0) },
            onViewportChanged: nil
        )
        coordinator.onExternalDrawingChange = { externalChangeCount += 1 }

        let canvasView = PKCanvasView()
        canvasView.delegate = coordinator
        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView
        let undoManager = UndoManager()
        let store = CanvasElementsStore()
        store.canvasReference = canvasReference
        store.undoManagerOverride = undoManager

        store.performTransaction("No-op") {}

        XCTAssertTrue(drawingChanges.isEmpty)
        XCTAssertEqual(externalChangeCount, 0)
        XCTAssertFalse(undoManager.canUndo)
    }

    private func makeStroke() -> PKStroke {
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 10, y: 12),
                timeOffset: 0,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 32, y: 36),
                timeOffset: 0.1,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
        ]
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
    }
}
