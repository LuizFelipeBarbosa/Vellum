import Foundation
import Observation

@MainActor
@Observable
final class NotePane: Identifiable {
    let id: UUID = UUID()
    let noteModel: NoteScreenModel
    let undoManager: UndoManager = UndoManager()
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
}
