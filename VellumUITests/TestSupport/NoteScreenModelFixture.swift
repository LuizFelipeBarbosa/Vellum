import Foundation
@testable import Vellum
import VellumCore

/// A note on disk together with the screen model that has finished loading it.
///
/// The container is live -- a real repository rooted at a temporary directory -- because these
/// tests are about what survives the save/load round trip, not about the model in isolation.
@MainActor
enum NoteScreenModelFixture {
    /// `configureNote` mutates the freshly created note and is saved before the model loads,
    /// so the model observes the mutated note rather than racing the write.
    static func make(
        rootDirectory: URL,
        title: String,
        configureNote: ((inout Note) -> Void)? = nil
    ) async throws -> (container: AppContainer, note: Note, model: NoteScreenModel) {
        let container = AppContainer.live(rootDirectory: rootDirectory)
        var note = try await container.notes.createNote(title: title)
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
        return (container, note, model)
    }
}
