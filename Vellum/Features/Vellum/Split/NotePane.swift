import Foundation
import Observation

@MainActor
@Observable
final class NotePane: Identifiable {
    let id: UUID = UUID()
    let noteModel: NoteScreenModel
    let undoManager: UndoManager = {
        let undoManager = UndoManager()
        // `PagedCanvasView.undoManager` in PencilCanvasView.swift returns this pane
        // manager, so the limit also bounds PencilKit's native stroke history. Fifty
        // keeps that history useful while capping the full editor snapshots it retains.
        undoManager.levelsOfUndo = 50
        return undoManager
    }()
    let canvasReference: NoteCanvasReference = NoteCanvasReference()
    private(set) var canvasGeneration: Int = 0
    var heightFraction: CGFloat

    var noteID: UUID { noteModel.noteID }

    init(noteModel: NoteScreenModel, heightFraction: CGFloat = 1) {
        self.noteModel = noteModel
        self.heightFraction = heightFraction
    }

    func canvasDidBecomeReady() {
        canvasGeneration += 1
    }

    func tearDown() {
        undoManager.removeAllActions()
        noteModel.detachViewCallbacks()
    }
}
