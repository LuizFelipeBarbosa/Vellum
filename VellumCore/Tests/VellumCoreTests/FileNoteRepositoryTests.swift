import Foundation
import Testing
@testable import VellumCore

@Test("Create, list, load, rename, and delete a note")
func noteLifecycle() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)

    var note = try await repository.createNote(title: "First title")
    #expect(note.revision == 1)
    #expect(note.pages.count == 1)

    let listed = try await repository.listNotes()
    #expect(listed.map(\.id) == [note.id])
    #expect(try await repository.loadNote(id: note.id).title == "First title")

    note.title = "Renamed"
    try await repository.saveNote(note)
    #expect(try await repository.loadNote(id: note.id).title == "Renamed")

    try await repository.deleteNote(id: note.id)
    #expect(try await repository.listNotes().isEmpty)
    await #expect(throws: VellumError.noteNotFound(note.id)) {
        try await repository.loadNote(id: note.id)
    }
}

@Test("Page plain text survives save and load")
func pagePlainTextRoundTrip() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)

    var note = try await repository.createNote(title: "Text")
    note.pages[0].plainText = "Ink and typed text coexist."
    try await repository.saveNote(note)

    let loaded = try await repository.loadNote(id: note.id)
    #expect(loaded.pages[0].plainText == "Ink and typed text coexist.")
}

@Test("Drawing data survives an asset round trip")
func binaryAssetRoundTrip() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Drawing")
    let bytes = Data([0x00, 0xFF, 0x42, 0x10, 0x80, 0x7F])

    try await repository.saveAsset(
        bytes,
        noteID: note.id,
        relativePath: note.pages[0].drawingAssetPath
    )

    let loaded = try await repository.loadAsset(
        noteID: note.id,
        relativePath: note.pages[0].drawingAssetPath
    )
    #expect(loaded == bytes)
}

@Test("Asset size reports byte count without requiring asset data")
func assetSize() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Drawing")
    let bytes = Data([0x00, 0xFF, 0x42, 0x10, 0x80, 0x7F])

    try await repository.saveAsset(
        bytes,
        noteID: note.id,
        relativePath: note.pages[0].drawingAssetPath
    )

    #expect(
        try await repository.assetSize(
            noteID: note.id,
            relativePath: note.pages[0].drawingAssetPath
        ) == bytes.count
    )
    #expect(
        try await repository.assetSize(
            noteID: note.id,
            relativePath: "assets/missing.data"
        ) == nil
    )
}

@Test("Unsafe asset paths are rejected", arguments: [
    "", "../x", "/abs", "a//b", "a/../../x", "pages/../..",
])
func invalidAssetPaths(path: String) async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Paths")

    await #expect(throws: VellumError.invalidAssetPath(path)) {
        try await repository.saveAsset(Data([1]), noteID: note.id, relativePath: path)
    }
    await #expect(throws: VellumError.invalidAssetPath(path)) {
        _ = try await repository.loadAsset(noteID: note.id, relativePath: path)
    }
    await #expect(throws: VellumError.invalidAssetPath(path)) {
        _ = try await repository.assetSize(noteID: note.id, relativePath: path)
    }
}

@Test("Autosave cannot resurrect a deleted note")
func saveAfterDeleteDoesNotRecreatePackage() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Delete me")
    let package = root.appendingPathComponent("\(note.id.uuidString).native-note")

    try await repository.deleteNote(id: note.id)
    await #expect(throws: VellumError.noteNotFound(note.id)) {
        try await repository.saveNote(note)
    }
    #expect(!FileManager.default.fileExists(atPath: package.path))
}

@Test("A future schema version is reported explicitly")
func unsupportedSchemaVersion() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    var note = try await repository.createNote(title: "Future")
    note.schemaVersion = 999
    try await repository.saveNote(note)

    await #expect(
        throws: VellumError.unsupportedSchemaVersion(
            found: 999,
            supported: Note.currentSchemaVersion
        )
    ) {
        try await repository.loadNote(id: note.id)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("VellumCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
