import Foundation
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class ErrorSurfacingTests: XCTestCase {
    func testTodayRefreshSurfacesCorruptNotePackage() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let container = AppContainer.live(rootDirectory: rootDirectory)
        let note = try await container.notes.createNote(title: "Corrupt Today note")
        try corruptPackage(for: note.id, under: rootDirectory)

        let model = TodayScreenModel(container: container)
        await model.refresh()

        XCTAssertNotNil(model.errorMessage)
    }

    func testGraphRefreshSurfacesCorruptNotePackage() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let container = AppContainer.live(rootDirectory: rootDirectory)
        let note = try await container.notes.createNote(title: "Corrupt Graph note")
        try corruptPackage(for: note.id, under: rootDirectory)

        let model = GraphScreenModel(container: container)
        await model.refresh()

        XCTAssertNotNil(model.errorMessage)
    }

    private func corruptPackage(for noteID: UUID, under rootDirectory: URL) throws {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: rootDirectory,
                includingPropertiesForKeys: [.isRegularFileKey]
            ),
            "could not enumerate the temporary workspace"
        )
        let noteIDComponent = noteID.uuidString.lowercased()
        let packageFiles = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.path.lowercased().contains(noteIDComponent),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return url
        }
        _ = try XCTUnwrap(
            packageFiles.first,
            "created note package contained no regular file to corrupt"
        )

        let corruptData = Data("not valid".utf8)
        for packageFile in packageFiles {
            try corruptData.write(to: packageFile, options: .atomic)
        }
    }
}
