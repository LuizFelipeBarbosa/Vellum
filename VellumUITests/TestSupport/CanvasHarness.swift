import Foundation
import PencilKit
@testable import Vellum
import VellumCore

/// The object graph a canvas-selection test needs, wired the way the app wires it: a canvas, the
/// reference the store and controller both resolve through, and an undo manager the store
/// records into instead of reaching for the responder chain's.
@MainActor
struct CanvasHarness {
    let canvasView: PKCanvasView
    let canvasReference: NoteCanvasReference
    let store: CanvasElementsStore
    let undoManager: UndoManager
    let controller: CanvasSelectionController

    /// Hydration registers undo actions of its own, so they are cleared before the harness is
    /// handed back -- a test's first undo must be the operation the test performed.
    static func make(
        strokes: [PKStroke] = [],
        elements: [CanvasElement]
    ) -> CanvasHarness {
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

        return CanvasHarness(
            canvasView: canvasView,
            canvasReference: canvasReference,
            store: store,
            undoManager: undoManager,
            controller: controller
        )
    }
}
