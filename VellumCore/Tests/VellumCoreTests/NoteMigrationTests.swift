import Foundation
import Testing
@testable import VellumCore

@Test("A v1 manifest decodes with knowledge defaults")
func v1ManifestDefaults() throws {
    let original = migrationNote(schemaVersion: 1)
    let encoded = try FilePersistence.encoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "noteType")
    object.removeValue(forKey: "spaceID")
    object.removeValue(forKey: "links")
    object.removeValue(forKey: "deletedAt")
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try FilePersistence.decoder().decode(Note.self, from: data)
    #expect(decoded.schemaVersion == 1)
    #expect(decoded.noteType == .note)
    #expect(decoded.spaceID == nil)
    #expect(decoded.links.isEmpty)
    #expect(decoded.deletedAt == nil)
    #expect(!decoded.isTrashed)
}

@Test("A v2 manifest decodes with soft-delete defaults")
func v2ManifestDefaults() throws {
    let original = migrationNote(schemaVersion: 2)
    let encoded = try FilePersistence.encoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "deletedAt")
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try FilePersistence.decoder().decode(Note.self, from: data)
    #expect(decoded.schemaVersion == 2)
    #expect(decoded.deletedAt == nil)
    #expect(!decoded.isTrashed)
}

@Test("A full v2 note round trips every knowledge field")
func v2NoteRoundTrip() throws {
    let spaceID = UUID()
    let targetID = UUID()
    let link = NoteLink(id: UUID(), targetNoteID: targetID, kind: .related, createdAt: Date(timeIntervalSince1970: 4))
    var note = migrationNote(schemaVersion: 2)
    note.noteType = .deck
    note.spaceID = spaceID
    note.links = [link]

    let decoded = try FilePersistence.decoder().decode(
        Note.self,
        from: FilePersistence.encoder().encode(note)
    )
    #expect(decoded.id == note.id)
    #expect(decoded.noteType == .deck)
    #expect(decoded.spaceID == spaceID)
    #expect(decoded.links == [link])
}

@Test("Saving a v1 note normalizes its schema version to v3")
func saveNormalizesSchemaVersion() async throws {
    let root = try migrationTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = migrationNote(schemaVersion: 1)
    try await repository.insertNote(note)

    try await repository.saveNote(note)

    #expect(try await repository.loadNote(id: note.id).schemaVersion == 3)
}

@Test("A future inserted manifest is rejected")
func insertedFutureSchemaIsRejected() async throws {
    let root = try migrationTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = migrationNote(schemaVersion: 4)
    try await repository.insertNote(note)

    await #expect(throws: VellumError.unsupportedSchemaVersion(found: 4, supported: 3)) {
        try await repository.loadNote(id: note.id)
    }
}

@Test("Insert note preserves IDs and creates every package directory")
func insertNoteCreatesSuppliedSkeleton() async throws {
    let root = try migrationTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = migrationNote(schemaVersion: 2)

    try await repository.insertNote(note)

    let package = root.appendingPathComponent("\(note.id.uuidString).native-note")
    #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("manifest.json").path))
    #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("pages/\(note.pages[0].id.uuidString)").path))
    for name in ["assets", "derived", "proposals", "operations"] {
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent(name).path))
    }
    #expect(try await repository.loadNote(id: note.id).pages[0].id == note.pages[0].id)
}

private func migrationNote(schemaVersion: Int) -> Note {
    let pageID = UUID()
    return Note(
        id: UUID(),
        schemaVersion: schemaVersion,
        revision: 1,
        title: "Migration",
        tags: ["test"],
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        pages: [
            NotePage(
                id: pageID,
                order: 0,
                plainText: "Legacy text",
                drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
                background: .blank
            )
        ]
    )
}

private func migrationTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("VellumCoreMigrationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
