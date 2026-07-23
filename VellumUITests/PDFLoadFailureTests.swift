import Foundation
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class PDFLoadFailureTests: XCTestCase {
    func testMissingPDFAssetSurfacesFailureWithoutBlockingEditing() async throws {
        let rootDirectory = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let assetPath = "assets/missing.pdf"
        let (_, model) = try await makeLoadedModel(
            rootDirectory: rootDirectory,
            title: "Missing PDF",
            assetPath: assetPath
        )

        XCTAssertEqual(model.pdfLoadFailures[assetPath], .missing)
        XCTAssertNotNil(model.note)
        XCTAssertTrue(model.hasEditablePage)
        XCTAssertNotNil(model.errorMessage)
    }

    func testUndecodablePDFAssetRecordsFailure() async throws {
        let rootDirectory = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let assetPath = "assets/undecodable.pdf"
        let (_, model) = try await makeLoadedModel(
            rootDirectory: rootDirectory,
            title: "Undecodable PDF",
            assetPath: assetPath,
            assetData: Data([0x00, 0xFF, 0x13, 0x37])
        )

        XCTAssertEqual(model.pdfLoadFailures[assetPath], .undecodable)
    }

    func testRetryClearsFailureAndErrorAfterPDFBecomesAvailable() async throws {
        let rootDirectory = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let assetPath = "assets/retry.pdf"
        let (container, model) = try await makeLoadedModel(
            rootDirectory: rootDirectory,
            title: "Retry PDF",
            assetPath: assetPath
        )
        XCTAssertEqual(model.pdfLoadFailures[assetPath], .missing)
        XCTAssertNotNil(model.errorMessage)

        try await container.notes.saveAsset(
            makePDFData(),
            noteID: model.noteID,
            relativePath: assetPath
        )
        await model.retryPDFLoad()

        XCTAssertTrue(model.pdfLoadFailures.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    private func makePDFData() -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 480)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(bounds)
        }
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

    private func makeLoadedModel(
        rootDirectory: URL,
        title: String,
        assetPath: String,
        assetData: Data? = nil
    ) async throws -> (AppContainer, NoteScreenModel) {
        let container = AppContainer.live(rootDirectory: rootDirectory)
        let createdNote = try await container.notes.createNote(title: title)
        var note = try await container.notes.loadNote(id: createdNote.id)
        note.pages[0].background = .pdf
        note.pages[0].pdfPage = PDFPageReference(
            assetPath: assetPath,
            pageIndex: 0
        )
        try await container.notes.saveNote(note)
        if let assetData {
            try await container.notes.saveAsset(
                assetData,
                noteID: note.id,
                relativePath: assetPath
            )
        }

        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()
        return (container, model)
    }
}
