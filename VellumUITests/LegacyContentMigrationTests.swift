import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class LegacyContentMigrationTests: XCTestCase {
    func testMigratesOversizedDrawingAndElementsUniformly() throws {
        let drawing = makeDrawing(
            from: CGPoint(x: 100, y: 80),
            to: CGPoint(x: 1_300, y: 380)
        )
        let imageID = UUID()
        let imageElement = CanvasElement(
            id: imageID,
            content: .image(
                ImageContent(
                    assetPath: "images/legacy.jpg",
                    originalPixelSize: CanvasSize(width: 1_200, height: 800)
                )
            ),
            frame: CanvasRect(x: 1_200, y: 200, width: 300, height: 200),
            rotation: 0.4
        )
        let textID = UUID()
        let originalFontSize = 24.0
        let textElement = CanvasElement(
            id: textID,
            content: .text(
                TextBoxContent(
                    text: "Legacy text",
                    fontSize: originalFontSize,
                    color: CodableColor(red: 0.1, green: 0.2, blue: 0.3)
                )
            ),
            frame: CanvasRect(x: 120, y: 500, width: 240, height: 80)
        )
        let elements = [imageElement, textElement]
        let drawingMaxX = drawing.bounds.isNull ? 0 : drawing.bounds.maxX
        let contentMaxX = elements.reduce(drawingMaxX) { maximum, element in
            max(maximum, element.rotatedBoundingBox.maxX)
        }
        let factor = PageLayout.contentWidth / contentMaxX

        let result = LegacyContentMigrator.migrateIfNeeded(
            drawing: drawing,
            elements: elements,
            layoutVersion: 1
        )

        XCTAssertTrue(result.didMigrate)
        XCTAssertLessThanOrEqual(
            result.drawing.bounds.maxX,
            PageLayout.contentWidth + 0.01
        )
        let migratedImage = try XCTUnwrap(
            result.elements.first { $0.id == imageID }
        )
        XCTAssertLessThanOrEqual(
            migratedImage.rotatedBoundingBox.maxX,
            PageLayout.contentWidth + 0.01
        )
        XCTAssertEqual(
            drawing.bounds.width / drawing.bounds.height,
            result.drawing.bounds.width / result.drawing.bounds.height,
            accuracy: 0.01
        )

        let migratedText = try XCTUnwrap(
            result.elements.first { $0.id == textID }
        )
        guard case .text(let textContent) = migratedText.content else {
            return XCTFail("Expected migrated text content")
        }
        XCTAssertEqual(
            textContent.fontSize,
            originalFontSize * Double(factor),
            accuracy: 0.000_001
        )
        XCTAssertEqual(migratedImage.rotation, imageElement.rotation)
        XCTAssertEqual(migratedImage.content, imageElement.content)

        let secondResult = LegacyContentMigrator.migrateIfNeeded(
            drawing: result.drawing,
            elements: result.elements,
            layoutVersion: 1
        )
        XCTAssertFalse(secondResult.didMigrate)
        XCTAssertEqual(
            secondResult.drawing.dataRepresentation(),
            result.drawing.dataRepresentation()
        )
        XCTAssertEqual(secondResult.elements, result.elements)
    }

    func testCurrentLayoutContentBeyondPageWidthIsReturnedUnchanged() {
        let drawing = makeDrawing(
            from: CGPoint(x: 100, y: 80),
            to: CGPoint(x: 1_300, y: 380)
        )
        let elements = [
            CanvasElement(
                content: .image(
                    ImageContent(
                        assetPath: "images/current.jpg",
                        originalPixelSize: CanvasSize(width: 1_200, height: 800)
                    )
                ),
                frame: CanvasRect(x: 1_200, y: 200, width: 300, height: 200),
                rotation: 0.4
            ),
        ]
        let originalDrawingData = drawing.dataRepresentation()

        let result = LegacyContentMigrator.migrateIfNeeded(
            drawing: drawing,
            elements: elements,
            layoutVersion: Note.currentLayoutVersion
        )

        XCTAssertFalse(result.didMigrate)
        XCTAssertEqual(result.drawing.dataRepresentation(), originalDrawingData)
        XCTAssertEqual(result.elements, elements)
    }

    func testContentWithinPageWidthIsReturnedUnchanged() {
        let drawing = makeDrawing(
            from: CGPoint(x: 20, y: 30),
            to: CGPoint(x: 300, y: 180)
        )
        let elements = [
            CanvasElement(
                content: .text(
                    TextBoxContent(
                        text: "Already fits",
                        fontSize: 18,
                        color: CodableColor(red: 0, green: 0, blue: 0)
                    )
                ),
                frame: CanvasRect(x: 350, y: 100, width: 180, height: 60),
                rotation: 0.1
            ),
        ]
        let originalDrawingData = drawing.dataRepresentation()

        let result = LegacyContentMigrator.migrateIfNeeded(
            drawing: drawing,
            elements: elements,
            layoutVersion: 1
        )

        XCTAssertFalse(result.didMigrate)
        XCTAssertEqual(result.drawing.dataRepresentation(), originalDrawingData)
        XCTAssertEqual(result.elements, elements)
    }

    func testEmptyContentDoesNotMigrate() {
        let drawing = PKDrawing()
        let originalDrawingData = drawing.dataRepresentation()

        let result = LegacyContentMigrator.migrateIfNeeded(
            drawing: drawing,
            elements: [],
            layoutVersion: 1
        )

        XCTAssertFalse(result.didMigrate)
        XCTAssertEqual(result.drawing.dataRepresentation(), originalDrawingData)
        XCTAssertEqual(result.elements, [])
    }

    func testLoadMigratesAndAutosavesLegacyContent() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = FileNoteRepository(rootDirectory: rootDirectory)
        var note = try await repository.createNote(title: "Legacy migration")
        let drawing = makeDrawing(
            from: CGPoint(x: 80, y: 60),
            to: CGPoint(x: 1_320, y: 420)
        )
        let element = CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: "images/legacy.jpg",
                    originalPixelSize: CanvasSize(width: 1_600, height: 900)
                )
            ),
            frame: CanvasRect(x: 1_150, y: 500, width: 300, height: 180),
            rotation: 0.25
        )
        note.pages[0].elements = [element]
        note.layoutVersion = 1
        try await repository.saveAsset(
            drawing.dataRepresentation(),
            noteID: note.id,
            relativePath: note.pages[0].drawingAssetPath
        )
        try await repository.saveNote(note)

        let container = AppContainer.live(rootDirectory: rootDirectory)
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()

        let modelDrawingData = try XCTUnwrap(model.drawingData)
        let modelDrawing = try PKDrawing(data: modelDrawingData)
        XCTAssertLessThanOrEqual(
            modelDrawing.bounds.maxX,
            PageLayout.contentWidth + 0.01
        )
        XCTAssertEqual(model.canvasElements.elements.count, 1)
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(model.canvasElements.elements.first).rotatedBoundingBox.maxX,
            PageLayout.contentWidth + 0.01
        )
        XCTAssertEqual(model.saveState, .unsaved)

        await model.flushPendingSave()

        XCTAssertEqual(model.saveState, .saved)
        let freshRepository = FileNoteRepository(rootDirectory: rootDirectory)
        let reloadedNote = try await freshRepository.loadNote(id: note.id)
        XCTAssertEqual(reloadedNote.layoutVersion, Note.currentLayoutVersion)
        let reloadedElement = try XCTUnwrap(reloadedNote.pages.first?.elements.first)
        XCTAssertLessThanOrEqual(
            reloadedElement.rotatedBoundingBox.maxX,
            PageLayout.contentWidth + 0.01
        )
        let drawingPath = try XCTUnwrap(reloadedNote.pages.first?.drawingAssetPath)
        let loadedData = try await freshRepository.loadAsset(
            noteID: reloadedNote.id,
            relativePath: drawingPath
        )
        let reloadedData = try XCTUnwrap(loadedData)
        let reloadedDrawing = try PKDrawing(data: reloadedData)
        XCTAssertLessThanOrEqual(
            reloadedDrawing.bounds.maxX,
            PageLayout.contentWidth + 0.01
        )
    }

    func testLoadDoesNotScheduleSaveForContentThatAlreadyFits() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = FileNoteRepository(rootDirectory: rootDirectory)
        var note = try await repository.createNote(title: "Current content")
        let drawing = makeDrawing(
            from: CGPoint(x: 40, y: 50),
            to: CGPoint(x: 400, y: 300)
        )
        let element = CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Fits",
                    fontSize: 20,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: CanvasRect(x: 450, y: 100, width: 180, height: 60),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        note.pages[0].elements = [element]
        let originalDrawingData = drawing.dataRepresentation()
        let originalDrawingPath = note.pages[0].drawingAssetPath
        try await repository.saveAsset(
            originalDrawingData,
            noteID: note.id,
            relativePath: originalDrawingPath
        )
        try await repository.saveNote(note)

        let container = AppContainer.live(rootDirectory: rootDirectory)
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()

        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(model.drawingData, originalDrawingData)
        XCTAssertEqual(model.canvasElements.elements, [element])

        await model.flushPendingSave()

        let freshRepository = FileNoteRepository(rootDirectory: rootDirectory)
        let reloadedNote = try await freshRepository.loadNote(id: note.id)
        XCTAssertEqual(reloadedNote.revision, note.revision)
        XCTAssertEqual(reloadedNote.pages.first?.drawingAssetPath, originalDrawingPath)
    }

    func testLoadDoesNotMigrateOrSaveWhenDrawingDataCannotBeDecoded() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = FileNoteRepository(rootDirectory: rootDirectory)
        var note = try await repository.createNote(title: "Unreadable drawing")
        let element = CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Oversized",
                    fontSize: 24,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: CanvasRect(x: 1_200, y: 100, width: 300, height: 80)
        )
        let garbageDrawingData = Data([0x00, 0xFF, 0x13, 0x37, 0xDE, 0xAD, 0xBE, 0xEF])
        note.pages[0].elements = [element]
        note.layoutVersion = 1
        try await repository.saveAsset(
            garbageDrawingData,
            noteID: note.id,
            relativePath: note.pages[0].drawingAssetPath
        )
        try await repository.saveNote(note)

        let container = AppContainer.live(rootDirectory: rootDirectory)
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(model.drawingData, garbageDrawingData)

        let freshRepository = FileNoteRepository(rootDirectory: rootDirectory)
        let reloadedNote = try await freshRepository.loadNote(id: note.id)
        XCTAssertEqual(reloadedNote.layoutVersion, 1)
        let reloadedDrawingData = try await freshRepository.loadAsset(
            noteID: note.id,
            relativePath: note.pages[0].drawingAssetPath
        )
        XCTAssertEqual(reloadedDrawingData, garbageDrawingData)
    }

    private func makeDrawing(from start: CGPoint, to end: CGPoint) -> PKDrawing {
        let controlPoints = [
            PKStrokePoint(
                location: start,
                timeOffset: 0,
                size: CGSize(width: 8, height: 8),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: end,
                timeOffset: 0.1,
                size: CGSize(width: 8, height: 8),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
        ]
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        )
        return PKDrawing(strokes: [stroke])
    }
}
