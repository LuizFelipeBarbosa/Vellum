import Foundation
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class UnsupportedNotesSurfacingTests: XCTestCase {
    func testRefreshCountsFutureSchemaNotePackages() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let container = AppContainer.live(rootDirectory: rootDirectory)
        _ = try await container.notes.createNote(title: "Supported note")

        let futurePackage = rootDirectory.appendingPathComponent(
            "\(UUID().uuidString).native-note",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: futurePackage,
            withIntermediateDirectories: true
        )
        let manifest = futurePackage.appendingPathComponent("manifest.json")
        try Data(#"{"schemaVersion":99}"#.utf8).write(to: manifest)

        let model = LibraryScreenModel(workspace: container.workspace)
        await model.refresh()

        XCTAssertEqual(model.unsupportedNoteCount, 1)
    }
}
