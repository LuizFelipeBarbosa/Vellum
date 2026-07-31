import Foundation
@testable import Vellum
import VellumCore
import XCTest

/// Page mutations must report rejection so callers (the pages panel's
/// thumbnail cache) never remap optimistically for a move or delete that
/// the model refused.
@MainActor
final class PageMutationRejectionTests: XCTestCase {
    func testMovePagesReportsRejectionWithoutCanvas() async throws {
        let rootDirectory = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let model = try await makeLoadedModel(rootDirectory: rootDirectory)

        XCTAssertFalse(
            model.movePages(source: IndexSet(integer: 0), to: 1),
            "movePages must report rejection when no canvas is attached"
        )
    }

    func testDeletePageReportsRejectionWithoutCanvas() async throws {
        let rootDirectory = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let model = try await makeLoadedModel(rootDirectory: rootDirectory)

        XCTAssertFalse(
            model.deletePage(at: 0),
            "deletePage must report rejection when no canvas is attached"
        )
    }

    func testSetPageOrientationReportsRejectionWithoutCanvas() async throws {
        let rootDirectory = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let model = try await makeLoadedModel(rootDirectory: rootDirectory)

        XCTAssertFalse(
            model.setPageOrientation(.landscape),
            "setPageOrientation must report rejection when no canvas is attached"
        )
    }

    private func makeRootDirectory() throws -> URL {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        return rootDirectory
    }

    private func makeLoadedModel(rootDirectory: URL) async throws -> NoteScreenModel {
        let container = AppContainer.live(rootDirectory: rootDirectory)
        let note = try await container.notes.createNote(title: "Rejection")
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()
        return model
    }
}
