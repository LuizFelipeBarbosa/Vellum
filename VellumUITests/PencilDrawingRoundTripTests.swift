import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class PencilDrawingRoundTripTests: XCTestCase {
    func testEmptyDrawingRoundTripsThroughFileRepository() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = FileNoteRepository(rootDirectory: rootDirectory)
        let note = try await repository.createNote(title: "Drawing round trip")
        let page = try XCTUnwrap(note.pages.first)
        let originalDrawing = PKDrawing()
        let originalData = originalDrawing.dataRepresentation()

        try await repository.saveAsset(
            originalData,
            noteID: note.id,
            relativePath: page.drawingAssetPath
        )
        let loadedData = try await repository.loadAsset(
            noteID: note.id,
            relativePath: page.drawingAssetPath
        )
        let unwrappedData = try XCTUnwrap(loadedData)
        let roundTrippedDrawing = try PKDrawing(data: unwrappedData)

        XCTAssertEqual(unwrappedData, originalData)
        XCTAssertEqual(roundTrippedDrawing.strokes.count, originalDrawing.strokes.count)
        XCTAssertEqual(roundTrippedDrawing.bounds, originalDrawing.bounds)
        XCTAssertFalse(roundTrippedDrawing.dataRepresentation().isEmpty)
    }

    func testRepositoryRejectsInvalidAssetPath() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = FileNoteRepository(rootDirectory: rootDirectory)
        let note = try await repository.createNote(title: "Invalid path")
        let invalidPath = "../outside.drawing"

        do {
            try await repository.saveAsset(
                Data(),
                noteID: note.id,
                relativePath: invalidPath
            )
            XCTFail("Expected an invalidAssetPath error")
        } catch let error as VellumError {
            XCTAssertEqual(error, .invalidAssetPath(invalidPath))
        }
    }

    func testNoteScreenModelDrawingRoundTripsThroughAutosavePath() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let container = AppContainer.live(rootDirectory: rootDirectory)
        let note = try await container.notes.createNote(title: "Note screen drawing")
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()

        let controlPoints = [
            PKStrokePoint(
                location: CGPoint(x: 10, y: 12),
                timeOffset: 0,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 32, y: 36),
                timeOffset: 0.1,
                size: CGSize(width: 4, height: 4),
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
        let drawing = PKDrawing(strokes: [stroke])

        model.drawingChanged(drawing.dataRepresentation())
        await model.flushPendingSave()

        let freshRepository = FileNoteRepository(rootDirectory: rootDirectory)
        let reloadedNote = try await freshRepository.loadNote(id: note.id)
        let drawingPath = try XCTUnwrap(reloadedNote.pages.first?.drawingAssetPath)
        let loadedData = try await freshRepository.loadAsset(
            noteID: reloadedNote.id,
            relativePath: drawingPath
        )
        let reloadedData = try XCTUnwrap(loadedData)
        let reloadedDrawing = try PKDrawing(data: reloadedData)

        XCTAssertEqual(reloadedDrawing.strokes.count, 1)
    }
}
