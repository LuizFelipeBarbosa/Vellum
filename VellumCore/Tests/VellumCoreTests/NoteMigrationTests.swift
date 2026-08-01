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

@Test("A manifest without a layout version defaults to legacy layout v1")
func manifestWithoutLayoutVersionDefaultsToV1() throws {
    let original = migrationNote(schemaVersion: 4)
    let encoded = try FilePersistence.encoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "layoutVersion")
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try FilePersistence.decoder().decode(Note.self, from: data)
    #expect(decoded.layoutVersion == 1)
}

@Test("A note round trips an explicit layout version")
func layoutVersionRoundTrip() throws {
    let pageID = UUID()
    let note = Note(
        id: UUID(),
        schemaVersion: 4,
        revision: 1,
        layoutVersion: 7,
        title: "Layout version",
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

    let decoded = try FilePersistence.decoder().decode(
        Note.self,
        from: FilePersistence.encoder().encode(note)
    )
    #expect(decoded.layoutVersion == 7)
}

@Test("A newly constructed note uses the current layout version")
func newNoteUsesCurrentLayoutVersion() {
    let note = migrationNote(schemaVersion: Note.currentSchemaVersion)

    #expect(note.layoutVersion == Note.currentLayoutVersion)
}

@Test("A newly constructed current note preserves its layout version through encoding")
func currentNoteLayoutVersionRoundTrip() throws {
    let note = migrationNote(schemaVersion: Note.currentSchemaVersion)

    let decoded = try FilePersistence.decoder().decode(
        Note.self,
        from: FilePersistence.encoder().encode(note)
    )
    #expect(decoded.layoutVersion == Note.currentLayoutVersion)
}

@Test("A manifest without page orientation defaults to portrait")
func manifestWithoutPageOrientationDefaultsToPortrait() throws {
    let encoded = try FilePersistence.encoder().encode(
        migrationNote(schemaVersion: Note.currentSchemaVersion)
    )
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "pageOrientation")
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try FilePersistence.decoder().decode(Note.self, from: data)

    #expect(decoded.pageOrientation == .portrait)
    #expect(decoded.pageGeometry == .a4)
}

@Test("An unknown page orientation defaults to portrait")
func unknownPageOrientationDefaultsToPortrait() throws {
    let encoded = try FilePersistence.encoder().encode(
        migrationNote(schemaVersion: Note.currentSchemaVersion)
    )
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["pageOrientation"] = "future-orientation"
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try FilePersistence.decoder().decode(Note.self, from: data)

    #expect(decoded.pageOrientation == .portrait)
    #expect(decoded.pageGeometry == .a4)
}

@Test("Page orientation round trips through persistence")
func pageOrientationRoundTripsThroughPersistence() throws {
    var note = migrationNote(schemaVersion: Note.currentSchemaVersion)
    note.pageOrientation = .landscape

    let decoded = try FilePersistence.decoder().decode(
        Note.self,
        from: FilePersistence.encoder().encode(note)
    )

    #expect(decoded.pageOrientation == .landscape)
    #expect(decoded.pageGeometry == .a4Landscape)
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

@Test("Saving a v1 note normalizes its schema version to the current version")
func saveNormalizesSchemaVersion() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = migrationNote(schemaVersion: 1)
    try await repository.insertNote(note)

    try await repository.saveNote(note)

    #expect(try await repository.loadNote(id: note.id).schemaVersion == Note.currentSchemaVersion)
}

@Test("A future inserted manifest is rejected")
func insertedFutureSchemaIsRejected() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let note = migrationNote(schemaVersion: Note.currentSchemaVersion + 1)
    try await repository.insertNote(note)

    await #expect(
        throws: VellumError.unsupportedSchemaVersion(
            found: Note.currentSchemaVersion + 1,
            supported: Note.currentSchemaVersion
        )
    ) {
        try await repository.loadNote(id: note.id)
    }
}

@Test("A v3 manifest decodes pages with an empty canvas")
func v3ManifestDefaultsCanvasElements() throws {
    let data = Data(
        """
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "schemaVersion": 3,
          "revision": 1,
          "title": "Legacy canvas",
          "tags": ["migration"],
          "createdAt": "1970-01-01T00:00:01.000Z",
          "updatedAt": "1970-01-01T00:00:02.000Z",
          "pages": [
            {
              "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
              "order": 0,
              "plainText": "Before elements",
              "drawingAssetPath": "pages/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB/drawing.data",
              "background": "blank"
            }
          ],
          "noteType": "note",
          "links": []
        }
        """.utf8
    )

    let note = try FilePersistence.decoder().decode(Note.self, from: data)

    #expect(note.schemaVersion == 3)
    #expect(note.pages[0].elements == [])
}

@Test("A v4 manifest preserves text and image canvas elements through persistence")
func v4ManifestCanvasElementsRoundTrip() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = FileNoteRepository(rootDirectory: root)
    let data = Data(
        """
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "schemaVersion": 4,
          "revision": 1,
          "title": "Canvas",
          "tags": ["migration"],
          "createdAt": "1970-01-01T00:00:01.000Z",
          "updatedAt": "1970-01-01T00:00:02.000Z",
          "pages": [
            {
              "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
              "order": 0,
              "plainText": "Elements",
              "drawingAssetPath": "pages/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB/drawing.data",
              "background": "grid",
              "elements": [
                {
                  "id": "11111111-1111-1111-1111-111111111111",
                  "kind": "text",
                  "text": {
                    "text": "Caption",
                    "fontSize": 20,
                    "color": { "red": 0.25, "green": 0.5, "blue": 0.75, "alpha": 1 }
                  },
                  "frame": { "x": 10, "y": 20, "width": 240, "height": 60 },
                  "rotation": 0.125,
                  "createdAt": "1970-01-01T00:00:03.000Z"
                },
                {
                  "id": "22222222-2222-2222-2222-222222222222",
                  "kind": "image",
                  "image": {
                    "assetPath": "assets/photo.jpg",
                    "originalPixelSize": { "width": 1600, "height": 1200 }
                  },
                  "frame": { "x": 30, "y": 40, "width": 400, "height": 300 },
                  "rotation": -0.25,
                  "createdAt": "1970-01-01T00:00:04.000Z"
                }
              ]
            }
          ],
          "noteType": "note",
          "links": []
        }
        """.utf8
    )
    let note = try FilePersistence.decoder().decode(Note.self, from: data)

    try await repository.insertNote(note)
    let loaded = try await repository.loadNote(id: note.id)

    #expect(loaded.schemaVersion == 4)
    #expect(loaded.pages[0].elements == note.pages[0].elements)
}

@Test("Insert note preserves IDs and creates every package directory")
func insertNoteCreatesSuppliedSkeleton() async throws {
    let root = try TemporaryDirectory.make()
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

@Test("A manifest without a background style defaults to legacy dots")
func manifestWithoutBackgroundStyleDefaultsToLegacyDots() throws {
    let original = migrationNote(schemaVersion: 5)
    let encoded = try FilePersistence.encoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "backgroundStyle")
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try FilePersistence.decoder().decode(Note.self, from: data)

    #expect(decoded.backgroundStyle == .legacyDefault)
}

@Test("A v6 manifest round trips an explicit background style")
func v6ManifestBackgroundStyleRoundTrip() throws {
    var note = migrationNote(schemaVersion: 6)
    note.backgroundStyle = PageBackgroundStyle(
        kind: .ruled,
        spacing: 32,
        paperTint: CodableColor(hex: "#FAF3DC")
    )

    let decoded = try FilePersistence.decoder().decode(
        Note.self,
        from: FilePersistence.encoder().encode(note)
    )

    #expect(decoded.backgroundStyle == note.backgroundStyle)
}

@Test("A manifest with an unknown background kind decodes to blank")
func manifestWithUnknownBackgroundKindDecodesToBlank() throws {
    let original = migrationNote(schemaVersion: 6)
    let encoded = try FilePersistence.encoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var backgroundStyle = try #require(object["backgroundStyle"] as? [String: Any])
    backgroundStyle["kind"] = "hexagons"
    object["backgroundStyle"] = backgroundStyle
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try FilePersistence.decoder().decode(Note.self, from: data)

    #expect(decoded.backgroundStyle.kind == .blank)
}

@Test("A v6 manifest page without a PDF reference decodes with nil")
func v6ManifestWithoutPDFPageReferenceDefaultsToNil() throws {
    let original = migrationNote(schemaVersion: 6)
    let encoded = try FilePersistence.encoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var pages = try #require(object["pages"] as? [[String: Any]])
    pages[0].removeValue(forKey: "pdfPage")
    object["pages"] = pages
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try FilePersistence.decoder().decode(Note.self, from: data)

    #expect(decoded.schemaVersion == 6)
    #expect(decoded.pages[0].pdfPage == nil)
}

@Test("A PDF page reference round trips its asset path and page index")
func pdfPageReferenceRoundTrip() throws {
    let pageID = UUID()
    let reference = PDFPageReference(assetPath: "assets/pdf-1234.pdf", pageIndex: 7)
    let page = NotePage(
        id: pageID,
        order: 0,
        plainText: "",
        drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
        background: .pdf,
        pdfPage: reference
    )

    let decoded = try FilePersistence.decoder().decode(
        NotePage.self,
        from: FilePersistence.encoder().encode(page)
    )

    #expect(decoded.pdfPage?.assetPath == reference.assetPath)
    #expect(decoded.pdfPage?.pageIndex == reference.pageIndex)
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
