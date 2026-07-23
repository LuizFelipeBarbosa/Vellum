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

    func testReorderShapedTransactionFiresElementsCallbackExactlyOnce() {
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { _ in },
            onViewportChanged: nil
        )
        let canvasView = PKCanvasView()
        canvasView.delegate = coordinator
        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView
        let store = CanvasElementsStore()
        store.canvasReference = canvasReference
        store.undoManagerOverride = UndoManager()

        var pages = makePages(count: 2)
        store.pagesProvider = { pages }
        store.onPagesRestored = { pages = $0 }
        var elementsCallbackCount = 0
        store.onElementsChanged = { _ in elementsCallbackCount += 1 }

        store.performTransaction("Reorder Pages") {
            store.mutateDrawing { drawing in
                drawing.strokes.append(makeStroke())
            }
            store.replaceAllElements([])
            pages.swapAt(0, 1)
            pages[0].order = 0
            pages[1].order = 1
        }

        XCTAssertEqual(elementsCallbackCount, 1)
    }

    func testReorderShapedUndoAndRedoRestoreDrawingAndPagesTogether() {
        let originalDrawing = PKDrawing(strokes: [makeStroke()])
        let canvasView = PKCanvasView()
        canvasView.drawing = originalDrawing
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { _ in },
            onViewportChanged: nil
        )
        canvasView.delegate = coordinator

        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView
        let undoManager = UndoManager()
        let store = CanvasElementsStore()
        store.canvasReference = canvasReference
        store.undoManagerOverride = undoManager

        let originalPages = makePages(count: 2)
        var pages = originalPages
        store.pagesProvider = { pages }
        store.onPagesRestored = { pages = $0 }

        store.performTransaction("Reorder Pages") {
            store.mutateDrawing { drawing in
                drawing.strokes.append(makeStroke())
            }
            store.replaceAllElements([])
            pages = [originalPages[1], originalPages[0]]
            pages[0].order = 0
            pages[1].order = 1
        }

        XCTAssertEqual(canvasView.drawing.strokes.count, 2)
        XCTAssertEqual(pages.map(\.id), [originalPages[1].id, originalPages[0].id])

        undoManager.undo()

        let restoredStrokes = canvasView.drawing.strokes
        XCTAssertEqual(restoredStrokes.count, originalDrawing.strokes.count)
        XCTAssertEqual(
            restoredStrokes.first?.renderBounds,
            originalDrawing.strokes.first?.renderBounds
        )
        XCTAssertEqual(pages.map(\.id), originalPages.map(\.id))
        XCTAssertEqual(pages.map(\.order), [0, 1])

        undoManager.redo()

        XCTAssertEqual(canvasView.drawing.strokes.count, 2)
        XCTAssertEqual(pages.map(\.id), [originalPages[1].id, originalPages[0].id])
        XCTAssertEqual(pages.map(\.order), [0, 1])
    }

    func testPagesOnlyTransactionIsUndoableAndRedoable() {
        let undoManager = UndoManager()
        let store = CanvasElementsStore()
        store.undoManagerOverride = undoManager

        let originalPages = makePages(count: 1)
        var pages = originalPages
        store.pagesProvider = { pages }
        store.onPagesRestored = { pages = $0 }

        store.performTransaction("Add Page") {
            pages.append(makePages(count: 2)[1])
        }

        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertEqual(pages.map(\.id), originalPages.map(\.id))
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages.map(\.order), [0, 1])
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

    private func makePages(count: Int) -> [NotePage] {
        (0..<count).map { index in
            let pageID = UUID()
            return NotePage(
                id: pageID,
                order: index,
                plainText: "",
                drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
                background: .blank
            )
        }
    }
}
