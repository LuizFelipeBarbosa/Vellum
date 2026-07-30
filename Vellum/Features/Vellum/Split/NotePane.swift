import Foundation
import Observation

@MainActor
@Observable
final class NotePane: Identifiable {
    let id: UUID = UUID()
    let noteModel: NoteScreenModel
    let undoManager: UndoManager = UndoManager()
    let canvasReference: NoteCanvasReference = NoteCanvasReference()
    var widthFraction: CGFloat

    var noteID: UUID { noteModel.noteID }

    init(noteModel: NoteScreenModel, widthFraction: CGFloat = 1) {
        self.noteModel = noteModel
        self.widthFraction = widthFraction
    }
}
