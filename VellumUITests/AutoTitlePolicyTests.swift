import Foundation
@testable import Vellum
@testable import VellumCore
import XCTest

@MainActor
final class AutoTitlePolicyTests: XCTestCase {
    func testMatchingRecognitionAutoTitlesOnlyOnce() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let (_, _, model) = try await NoteScreenModelFixture.make(
            rootDirectory: rootDirectory,
            title: "Untitled"
        )
        let pageID = try XCTUnwrap(model.note?.pages.first?.id)
        let firstText = "First recognized sentence. More detail"

        model.applyRecognitionOutcome(
            try outcome(for: model, pageTexts: [pageID: firstText])
        )

        let firstTitle = TitleSuggestion.firstSentence(from: firstText)
        XCTAssertEqual(model.plainText, firstText)
        XCTAssertEqual(model.title, firstTitle)
        XCTAssertEqual(model.note?.titleOrigin, .auto)

        let secondText = "A later recognition result. More detail"
        model.applyRecognitionOutcome(
            try outcome(for: model, pageTexts: [pageID: secondText])
        )

        XCTAssertEqual(model.plainText, secondText)
        XCTAssertEqual(model.title, firstTitle)
        XCTAssertEqual(model.note?.titleOrigin, .auto)
    }

    func testStaleRecognitionOutcomeIsDroppedEntirely() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let (_, _, model) = try await NoteScreenModelFixture.make(
            rootDirectory: rootDirectory,
            title: "Untitled"
        )
        let pageID = try XCTUnwrap(model.note?.pages.first?.id)
        let staleOutcome = try outcome(
            for: model,
            pageTexts: [pageID: "Stale recognized text. More detail"]
        )

        model.drawingChanged(Data([0x01]))
        model.applyRecognitionOutcome(staleOutcome)

        XCTAssertEqual(model.plainText, "")
        XCTAssertEqual(model.title, "Untitled")
        XCTAssertEqual(model.note?.titleOrigin, .default)
    }

    func testHeaderTitleEditFreezesTitleAgainstRecognition() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let (_, _, model) = try await NoteScreenModelFixture.make(
            rootDirectory: rootDirectory,
            title: "Untitled"
        )
        let pageID = try XCTUnwrap(model.note?.pages.first?.id)

        model.title = "Something"
        XCTAssertEqual(model.note?.titleOrigin, .manual)

        let recognizedText = "Recognition should not replace this title. More detail"
        model.applyRecognitionOutcome(
            try outcome(for: model, pageTexts: [pageID: recognizedText])
        )

        XCTAssertEqual(model.plainText, recognizedText)
        XCTAssertEqual(model.title, "Something")
        XCTAssertEqual(model.note?.titleOrigin, .manual)
    }

    func testExistingManualTitleIsNeverAutoTitled() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let (_, _, model) = try await NoteScreenModelFixture.make(
            rootDirectory: rootDirectory,
            title: "Untitled",
            configureNote: {
                $0.title = "Real Title"
                $0.titleOrigin = .manual
            }
        )
        let pageID = try XCTUnwrap(model.note?.pages.first?.id)
        let recognizedText = "A different suggested title. More detail"

        model.applyRecognitionOutcome(
            try outcome(for: model, pageTexts: [pageID: recognizedText])
        )

        XCTAssertEqual(model.plainText, recognizedText)
        XCTAssertEqual(model.title, "Real Title")
        XCTAssertEqual(model.note?.titleOrigin, .manual)
    }

    private func outcome(
        for model: NoteScreenModel,
        pageTexts: [UUID: String]
    ) throws -> TextRecognitionOutcome {
        let input = try XCTUnwrap(model.currentRecognitionInput())
        let fingerprint = TextRecognitionService.fingerprint(for: input)
        return TextRecognitionOutcome(
            noteID: input.noteID,
            fingerprint: fingerprint,
            pageTexts: pageTexts,
            document: RecognizedNoteText(
                schemaVersion: RecognizedNoteText.currentSchemaVersion,
                inputFingerprint: fingerprint,
                generatedAt: Date(),
                pages: []
            )
        )
    }
}
