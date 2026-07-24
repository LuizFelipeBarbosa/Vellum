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

    func testDeletePageTransactionUndoRestoresDrawingElementsAndPagesTogether() {
        let geometry = PageGeometry.a4
        let firstStroke = makeStroke()
        let deletedStroke = PKStroke(
            ink: firstStroke.ink,
            path: firstStroke.path,
            transform: firstStroke.transform.concatenating(
                CGAffineTransform(
                    translationX: 0,
                    y: geometry.pageHeight + 100
                )
            ),
            mask: firstStroke.mask,
            randomSeed: firstStroke.randomSeed
        )
        let laterStroke = PKStroke(
            ink: firstStroke.ink,
            path: firstStroke.path,
            transform: firstStroke.transform.concatenating(
                CGAffineTransform(
                    translationX: 0,
                    y: 2 * geometry.pageHeight + 100
                )
            ),
            mask: firstStroke.mask,
            randomSeed: firstStroke.randomSeed
        )
        let originalDrawing = PKDrawing(
            strokes: [firstStroke, deletedStroke, laterStroke]
        )
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

        let originalElements = [
            CanvasElement(
                content: .image(
                    ImageContent(
                        assetPath: "assets/first.jpg",
                        originalPixelSize: CanvasSize(width: 100, height: 100)
                    )
                ),
                frame: CanvasRect(x: 20, y: 30, width: 80, height: 60)
            ),
            CanvasElement(
                content: .image(
                    ImageContent(
                        assetPath: "assets/deleted.jpg",
                        originalPixelSize: CanvasSize(width: 100, height: 100)
                    )
                ),
                frame: CanvasRect(
                    x: 30,
                    y: Double(geometry.pageHeight + 40),
                    width: 80,
                    height: 60
                )
            ),
            CanvasElement(
                content: .image(
                    ImageContent(
                        assetPath: "assets/later.jpg",
                        originalPixelSize: CanvasSize(width: 100, height: 100)
                    )
                ),
                frame: CanvasRect(
                    x: 40,
                    y: Double(2 * geometry.pageHeight + 50),
                    width: 80,
                    height: 60
                )
            ),
        ]
        store.hydrate(originalElements)

        let originalPages = makePages(count: 3)
        var pages = originalPages
        store.pagesProvider = { pages }
        store.onPagesRestored = { pages = $0 }

        let result = PageDeleter.deletePage(
            at: 1,
            drawing: canvasView.drawing,
            elements: store.elements,
            pages: pages,
            geometry: geometry
        )
        store.performTransaction("Delete Page") {
            store.mutateDrawing { $0 = result.drawing }
            store.replaceAllElements(result.elements)
            pages = result.pages
        }

        XCTAssertEqual(canvasView.drawing.strokes.count, 2)
        XCTAssertEqual(store.elements.count, 2)
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertEqual(pages.count, originalPages.count)
        XCTAssertEqual(pages.map(\.id), originalPages.map(\.id))
        XCTAssertEqual(pages.map(\.order), originalPages.map(\.order))
        XCTAssertEqual(store.elements, originalElements)

        let restoredStrokes = canvasView.drawing.strokes
        XCTAssertEqual(restoredStrokes.count, originalDrawing.strokes.count)
        for (restoredStroke, originalStroke) in zip(
            restoredStrokes,
            originalDrawing.strokes
        ) {
            XCTAssertEqual(
                restoredStroke.renderBounds.minX,
                originalStroke.renderBounds.minX,
                accuracy: 0.5
            )
            XCTAssertEqual(
                restoredStroke.renderBounds.minY,
                originalStroke.renderBounds.minY,
                accuracy: 0.5
            )
            XCTAssertEqual(
                restoredStroke.renderBounds.width,
                originalStroke.renderBounds.width,
                accuracy: 0.5
            )
            XCTAssertEqual(
                restoredStroke.renderBounds.height,
                originalStroke.renderBounds.height,
                accuracy: 0.5
            )
        }
    }

    func testDeletePageZeroTransactionUndoAndRedoKeepPageZeroElementsMirroringStore() {
        let geometry = PageGeometry.a4
        let deletedStroke = makeStroke()
        let survivorStroke = PKStroke(
            ink: deletedStroke.ink,
            path: deletedStroke.path,
            transform: deletedStroke.transform.concatenating(
                CGAffineTransform(
                    translationX: 0,
                    y: geometry.pageHeight + 100
                )
            ),
            mask: deletedStroke.mask,
            randomSeed: deletedStroke.randomSeed
        )
        let originalDrawing = PKDrawing(strokes: [deletedStroke, survivorStroke])
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

        let originalElements = [
            CanvasElement(
                content: .image(
                    ImageContent(
                        assetPath: "assets/deleted.jpg",
                        originalPixelSize: CanvasSize(width: 100, height: 100)
                    )
                ),
                frame: CanvasRect(x: 20, y: 30, width: 80, height: 60)
            ),
            CanvasElement(
                content: .image(
                    ImageContent(
                        assetPath: "assets/survivor.jpg",
                        originalPixelSize: CanvasSize(width: 100, height: 100)
                    )
                ),
                frame: CanvasRect(
                    x: 40,
                    y: Double(geometry.pageHeight + 50),
                    width: 80,
                    height: 60
                )
            ),
        ]
        store.hydrate(originalElements)

        let firstPageID = UUID()
        let secondPageID = UUID()
        let originalPages = [
            NotePage(
                id: firstPageID,
                order: 0,
                plainText: "",
                drawingAssetPath: "pages/\(firstPageID.uuidString)/drawing.data",
                background: .blank,
                elements: originalElements
            ),
            NotePage(
                id: secondPageID,
                order: 1,
                plainText: "",
                drawingAssetPath: "pages/\(secondPageID.uuidString)/drawing.data",
                background: .blank
            ),
        ]
        var pages = originalPages
        store.pagesProvider = { pages }
        store.onPagesRestored = { pages = $0 }

        let result = PageDeleter.deletePage(
            at: 0,
            drawing: canvasView.drawing,
            elements: store.elements,
            pages: pages,
            geometry: geometry
        )
        store.performTransaction("Delete Page") {
            store.mutateDrawing { $0 = result.drawing }
            store.replaceAllElements(result.elements)
            pages = result.pages
        }

        XCTAssertEqual(store.elements, result.elements)
        XCTAssertEqual(pages[0].elements, result.elements)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertEqual(pages.count, originalPages.count)
        XCTAssertEqual(pages.map(\.id), originalPages.map(\.id))
        XCTAssertEqual(pages.map(\.order), originalPages.map(\.order))
        XCTAssertEqual(store.elements, originalElements)

        let restoredStrokes = canvasView.drawing.strokes
        XCTAssertEqual(restoredStrokes.count, originalDrawing.strokes.count)
        for (restoredStroke, originalStroke) in zip(
            restoredStrokes,
            originalDrawing.strokes
        ) {
            XCTAssertEqual(
                restoredStroke.renderBounds.minX,
                originalStroke.renderBounds.minX,
                accuracy: 0.5
            )
            XCTAssertEqual(
                restoredStroke.renderBounds.minY,
                originalStroke.renderBounds.minY,
                accuracy: 0.5
            )
            XCTAssertEqual(
                restoredStroke.renderBounds.width,
                originalStroke.renderBounds.width,
                accuracy: 0.5
            )
            XCTAssertEqual(
                restoredStroke.renderBounds.height,
                originalStroke.renderBounds.height,
                accuracy: 0.5
            )
        }

        undoManager.redo()

        XCTAssertEqual(store.elements, result.elements)
        XCTAssertEqual(pages[0].elements, store.elements)
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
