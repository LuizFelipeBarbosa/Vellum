import Foundation
import Testing
@testable import VellumCore

@Test("Create, list, load, rename, and delete a note")
func noteLifecycle() async throws {
    let root = try TemporaryDirectory.make()
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

@Test("Note listing scopes filter active and trashed notes")
func noteListingScopes() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let active = try await repository.createNote(title: "Active")
    var trashed = try await repository.createNote(title: "Trashed")
    trashed.deletedAt = Date(timeIntervalSince1970: 10)
    try await repository.saveNote(trashed)

    let activeNotes = try await repository.listNotes(scope: .active)
    let trashedNotes = try await repository.listNotes(scope: .trashed)
    let allNotes = try await repository.listNotes(scope: .all)

    #expect(activeNotes.map(\.id) == [active.id])
    #expect(trashedNotes.map(\.id) == [trashed.id])
    #expect(Set(allNotes.map(\.id)) == Set([active.id, trashed.id]))
    #expect(try await repository.listNotes().map(\.id) == activeNotes.map(\.id))
}

@Test("Page plain text survives save and load")
func pagePlainTextRoundTrip() async throws {
    let root = try TemporaryDirectory.make()
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
    let root = try TemporaryDirectory.make()
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

@Test("Importing a note atomically persists its manifest and assets")
func atomicNoteImport() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let pageID = UUID()
    let note = Note(
        id: UUID(),
        schemaVersion: Note.currentSchemaVersion,
        revision: 1,
        title: "Imported",
        tags: [],
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        pages: [
            NotePage(
                id: pageID,
                order: 0,
                plainText: "",
                drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
                background: .blank
            )
        ],
        backgroundStyle: .blank
    )
    let assetPath = "assets/source.pdf"
    let bytes = Data([0x25, 0x50, 0x44, 0x46])

    try await repository.importNote(
        note,
        assets: [(relativePath: assetPath, data: bytes)]
    )

    #expect(try await repository.listNotes(scope: .all).map(\.id) == [note.id])
    let loaded = try await repository.loadNote(id: note.id)
    #expect(
        try FilePersistence.encoder().encode(loaded)
            == FilePersistence.encoder().encode(note)
    )
    #expect(
        try await repository.loadAsset(
            noteID: note.id,
            relativePath: assetPath
        ) == bytes
    )
}

@Test("A failed atomic import leaves no package or staging directory")
func failedAtomicNoteImportLeavesNoTrace() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let pageID = UUID()
    let note = Note(
        id: UUID(),
        schemaVersion: Note.currentSchemaVersion,
        revision: 1,
        title: "Invalid import",
        tags: [],
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        pages: [
            NotePage(
                id: pageID,
                order: 0,
                plainText: "",
                drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
                background: .blank
            )
        ],
        backgroundStyle: .blank
    )
    let invalidPath = "assets/../escape.pdf"

    await #expect(throws: VellumError.invalidAssetPath(invalidPath)) {
        try await repository.importNote(
            note,
            assets: [(relativePath: invalidPath, data: Data([0x01]))]
        )
    }

    let listed = try await repository.listNotes(scope: .all)
    #expect(!listed.contains { $0.id == note.id })
    let package = FilePersistence.packageURL(rootDirectory: root, noteID: note.id)
    #expect(!FileManager.default.fileExists(atPath: package.path))
    let remainingEntries = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
    )
    #expect(remainingEntries.isEmpty)
}

@Test("Asset size reports byte count without requiring asset data")
func assetSize() async throws {
    let root = try TemporaryDirectory.make()
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
    let root = try TemporaryDirectory.make()
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
    await #expect(throws: VellumError.invalidAssetPath(path)) {
        try await repository.deleteAsset(noteID: note.id, relativePath: path)
    }
}

@Test("Autosave cannot resurrect a deleted note")
func saveAfterDeleteDoesNotRecreatePackage() async throws {
    let root = try TemporaryDirectory.make()
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

@Test("Loading an on-disk future schema version is reported explicitly")
func loadUnsupportedSchemaVersion() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    var note = try await repository.createNote(title: "Future")
    note.schemaVersion = 999
    let package = FilePersistence.packageURL(rootDirectory: root, noteID: note.id)
    try FilePersistence.write(note, to: package.appendingPathComponent("manifest.json"))

    await #expect(
        throws: VellumError.unsupportedSchemaVersion(
            found: 999,
            supported: Note.currentSchemaVersion
        )
    ) {
        try await repository.loadNote(id: note.id)
    }
}

@Test("Listing excludes future schemas while unsupported notes reports them")
func listNotesSkipsFutureSchemaVersion() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let current = try await repository.createNote(title: "Current")
    var future = try await repository.createNote(title: "Future")
    future.schemaVersion = 99
    let futurePackage = FilePersistence.packageURL(rootDirectory: root, noteID: future.id)
    try FilePersistence.write(future, to: futurePackage.appendingPathComponent("manifest.json"))

    let listed = try await repository.listNotes(scope: .all)
    let unsupported = try await repository.unsupportedNotes()

    #expect(listed.map(\.id) == [current.id])
    #expect(unsupported == [
        UnsupportedNotePackage(
            packageName: futurePackage.lastPathComponent,
            schemaVersion: 99
        )
    ])
}

@Test("Loading a manifest with a malformed known element reports corruption")
func loadNoteRejectsMalformedKnownElement() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Corrupt element")
    let package = FilePersistence.packageURL(rootDirectory: root, noteID: note.id)
    let manifest = package.appendingPathComponent("manifest.json")
    let originalData = try Data(contentsOf: manifest)
    var object = try #require(JSONSerialization.jsonObject(with: originalData) as? [String: Any])
    var pages = try #require(object["pages"] as? [[String: Any]])
    pages[0]["elements"] = [[
        "id": "22222222-2222-2222-2222-222222222222",
        "kind": "text",
        "text": 42,
        "frame": ["x": 0, "y": 0, "width": 100, "height": 40],
        "rotation": 0,
        "createdAt": "1970-01-01T00:00:02.000Z",
    ]]
    object["pages"] = pages
    let malformedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try malformedData.write(to: manifest, options: .atomic)

    await #expect(throws: VellumError.corruptManifest(note.id)) {
        try await repository.loadNote(id: note.id)
    }
    #expect(try Data(contentsOf: manifest) == malformedData)
}

@Test("Saving a future schema version is rejected without overwriting its manifest")
func saveNoteRejectsFutureSchemaVersion() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    var note = try await repository.createNote(title: "Original")
    let package = FilePersistence.packageURL(rootDirectory: root, noteID: note.id)
    let manifest = package.appendingPathComponent("manifest.json")
    let originalData = try Data(contentsOf: manifest)
    note.schemaVersion = Note.currentSchemaVersion + 1
    note.title = "Must not be written"

    await #expect(
        throws: VellumError.unsupportedSchemaVersion(
            found: Note.currentSchemaVersion + 1,
            supported: Note.currentSchemaVersion
        )
    ) {
        try await repository.saveNote(note)
    }

    let unchangedData = try Data(contentsOf: manifest)
    let loaded = try await repository.loadNote(id: note.id)
    #expect(unchangedData == originalData)
    #expect(loaded.schemaVersion == Note.currentSchemaVersion)
    #expect(loaded.title == "Original")
}

@Test("Deleting an asset removes it and ignores a missing file")
func deleteAsset() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Delete asset")
    let assetPath = note.pages[0].drawingAssetPath

    try await repository.saveAsset(Data([0x01]), noteID: note.id, relativePath: assetPath)
    try await repository.deleteAsset(noteID: note.id, relativePath: assetPath)
    #expect(try await repository.loadAsset(noteID: note.id, relativePath: assetPath) == nil)

    try await repository.deleteAsset(noteID: note.id, relativePath: assetPath)
}

@Test("Purging assets keeps referenced files and removes orphaned files")
func purgeUnreferencedAssets() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Purge drawings")
    let pageID = note.pages[0].id
    let referencedPath = "pages/\(pageID.uuidString)/drawing-kept.data"
    let unreferencedPath = "pages/\(pageID.uuidString)/drawing-orphan.data"
    let referencedImportedAssetPath = "assets/drawing-decoy.data"
    let unreferencedImportedAssetPath = "assets/orphan.bin"
    let referencedData = Data([0x01])
    let unreferencedData = Data([0x02])
    let referencedImportedData = Data([0x03])
    let unreferencedImportedData = Data([0x04])

    var savedNote = try await repository.loadNote(id: note.id)
    savedNote.pages[0].drawingAssetPath = referencedPath
    savedNote.pages[0].elements.append(
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: referencedImportedAssetPath,
                    originalPixelSize: CanvasSize(width: 1, height: 1)
                )
            ),
            frame: CanvasRect(x: 0, y: 0, width: 1, height: 1)
        )
    )
    try await repository.saveNote(savedNote)

    try await repository.saveAsset(referencedData, noteID: note.id, relativePath: referencedPath)
    try await repository.saveAsset(unreferencedData, noteID: note.id, relativePath: unreferencedPath)
    try await repository.saveAsset(
        referencedImportedData,
        noteID: note.id,
        relativePath: referencedImportedAssetPath
    )
    try await repository.saveAsset(
        unreferencedImportedData,
        noteID: note.id,
        relativePath: unreferencedImportedAssetPath
    )

    try await repository.purgeUnreferencedAssets(noteID: note.id)

    #expect(
        try await repository.loadAsset(noteID: note.id, relativePath: referencedPath) == referencedData
    )
    #expect(
        try await repository.loadAsset(noteID: note.id, relativePath: unreferencedPath) == nil
    )
    #expect(
        try await repository.loadAsset(
            noteID: note.id,
            relativePath: referencedImportedAssetPath
        ) == referencedImportedData
    )
    #expect(
        try await repository.loadAsset(
            noteID: note.id,
            relativePath: unreferencedImportedAssetPath
        ) == nil
    )
}

@Test("Purging image assets keeps references and removes orphans")
func purgeUnreferencedImageAssets() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Purge images")
    let referencedPath = "assets/\(UUID().uuidString).jpg"
    let unreferencedPath = "assets/\(UUID().uuidString).jpg"
    let referencedData = Data([0x10, 0x11])
    let unreferencedData = Data([0x12, 0x13])

    var savedNote = try await repository.loadNote(id: note.id)
    savedNote.pages[0].elements.append(
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: referencedPath,
                    originalPixelSize: CanvasSize(width: 1, height: 1)
                )
            ),
            frame: CanvasRect(x: 0, y: 0, width: 1, height: 1)
        )
    )
    try await repository.saveNote(savedNote)

    try await repository.saveAsset(referencedData, noteID: note.id, relativePath: referencedPath)
    try await repository.saveAsset(unreferencedData, noteID: note.id, relativePath: unreferencedPath)

    try await repository.purgeUnreferencedAssets(noteID: note.id)

    #expect(
        try await repository.loadAsset(noteID: note.id, relativePath: referencedPath) == referencedData
    )
    #expect(
        try await repository.loadAsset(noteID: note.id, relativePath: unreferencedPath) == nil
    )
}

@Test("Purging PDF assets keeps references and removes orphans")
func purgeUnreferencedPDFAssets() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Purge PDFs")
    let referencedPath = "assets/pdf-\(UUID().uuidString).pdf"
    let unreferencedPath = "assets/pdf-\(UUID().uuidString).pdf"
    let referencedData = Data([0x25, 0x50, 0x44, 0x46])
    let unreferencedData = Data([0x25, 0x50, 0x44, 0x47])

    var savedNote = try await repository.loadNote(id: note.id)
    savedNote.pages[0].pdfPage = PDFPageReference(assetPath: referencedPath, pageIndex: 0)
    try await repository.saveNote(savedNote)

    try await repository.saveAsset(referencedData, noteID: note.id, relativePath: referencedPath)
    try await repository.saveAsset(unreferencedData, noteID: note.id, relativePath: unreferencedPath)

    try await repository.purgeUnreferencedAssets(noteID: note.id)

    #expect(
        try await repository.loadAsset(noteID: note.id, relativePath: referencedPath) == referencedData
    )
    #expect(
        try await repository.loadAsset(noteID: note.id, relativePath: unreferencedPath) == nil
    )
}

@Test("An uncommitted shadow drawing is invisible and purged after reload")
func tornDrawingSaveIsInvisibleAndPurged() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Torn drawing")
    let oldAssetPath = note.pages[0].drawingAssetPath
    let newAssetPath = "pages/\(note.pages[0].id.uuidString)/drawing-\(UUID().uuidString).data"
    let oldData = Data([0x10, 0x20])
    let uncommittedData = Data([0x30, 0x40])

    let savedNote = try await repository.loadNote(id: note.id)
    try await repository.saveNote(savedNote)
    try await repository.saveAsset(oldData, noteID: note.id, relativePath: oldAssetPath)
    try await repository.saveAsset(uncommittedData, noteID: note.id, relativePath: newAssetPath)

    let reloadedNote = try await repository.loadNote(id: note.id)
    let reloadedAssetPath = reloadedNote.pages[0].drawingAssetPath
    #expect(reloadedAssetPath == oldAssetPath)
    #expect(
        try await repository.loadAsset(noteID: note.id, relativePath: reloadedAssetPath) == oldData
    )

    try await repository.purgeUnreferencedAssets(noteID: note.id)

    #expect(
        try await repository.loadAsset(noteID: note.id, relativePath: newAssetPath) == nil
    )
    #expect(
        try await repository.loadAsset(noteID: note.id, relativePath: oldAssetPath) == oldData
    )
}

@Test("Purging assets honors the latest manifest instead of an earlier snapshot")
func purgeHonorsLatestManifestNotStaleSnapshot() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = try await repository.createNote(title: "Latest purge manifest")
    let firstReferencedPath = "assets/\(UUID().uuidString).jpg"
    let orphanedPath = "assets/\(UUID().uuidString).jpg"
    let latestReferencedPath = "assets/\(UUID().uuidString).jpg"
    let firstReferencedData = Data([0x21])
    let orphanedData = Data([0x22])
    let latestReferencedData = Data([0x23])

    var savedNote = try await repository.loadNote(id: note.id)
    savedNote.pages[0].elements.append(
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: firstReferencedPath,
                    originalPixelSize: CanvasSize(width: 1, height: 1)
                )
            ),
            frame: CanvasRect(x: 0, y: 0, width: 1, height: 1)
        )
    )
    try await repository.saveNote(savedNote)
    try await repository.saveAsset(
        firstReferencedData,
        noteID: note.id,
        relativePath: firstReferencedPath
    )
    try await repository.saveAsset(orphanedData, noteID: note.id, relativePath: orphanedPath)

    savedNote.pages[0].elements.append(
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: latestReferencedPath,
                    originalPixelSize: CanvasSize(width: 1, height: 1)
                )
            ),
            frame: CanvasRect(x: 0, y: 0, width: 1, height: 1)
        )
    )
    try await repository.saveNote(savedNote)
    try await repository.saveAsset(
        latestReferencedData,
        noteID: note.id,
        relativePath: latestReferencedPath
    )

    try await repository.purgeUnreferencedAssets(noteID: note.id)

    #expect(
        try await repository.loadAsset(
            noteID: note.id,
            relativePath: firstReferencedPath
        ) == firstReferencedData
    )
    #expect(
        try await repository.loadAsset(noteID: note.id, relativePath: orphanedPath) == nil
    )
    #expect(
        try await repository.loadAsset(
            noteID: note.id,
            relativePath: latestReferencedPath
        ) == latestReferencedData
    )
}

@Test("A created note persists a blank background style")
func createdNotePersistsBlankBackgroundStyle() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)

    let note = try await repository.createNote(title: "Blank paper")
    #expect(note.backgroundStyle == .blank)

    try await repository.saveNote(note)
    let loaded = try await repository.loadNote(id: note.id)
    #expect(loaded.backgroundStyle == .blank)
}

@Test("Saving a legacy manifest upgrades its schema and preserves legacy dots")
func savingLegacyManifestUpgradesSchemaAndPreservesDots() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let pageID = UUID()
    let original = Note(
        id: UUID(),
        schemaVersion: 5,
        revision: 1,
        title: "Legacy paper",
        tags: [],
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        pages: [
            NotePage(
                id: pageID,
                order: 0,
                plainText: "",
                drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
                background: .blank
            )
        ]
    )
    let encoded = try FilePersistence.encoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "backgroundStyle")
    let data = try JSONSerialization.data(withJSONObject: object)
    let legacy = try FilePersistence.decoder().decode(Note.self, from: data)

    #expect(legacy.schemaVersion == 5)
    #expect(legacy.backgroundStyle == .legacyDefault)

    try await repository.insertNote(legacy)
    try await repository.saveNote(legacy)
    let loaded = try await repository.loadNote(id: legacy.id)
    #expect(loaded.schemaVersion == Note.currentSchemaVersion)
    #expect(loaded.backgroundStyle == .legacyDefault)
}
