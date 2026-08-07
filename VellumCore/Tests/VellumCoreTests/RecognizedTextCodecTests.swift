import Foundation
import Testing
@testable import VellumCore

@Test("Recognized note text round trips through Vellum JSON coding")
func recognizedNoteTextRoundTrip() throws {
    let pageID = UUID()
    let inkLine = RecognizedLine(
        text: "Written",
        rect: CanvasRect(x: 10, y: 20, width: 100, height: 30),
        confidence: 0.82,
        source: .ink
    )
    let typedLine = RecognizedLine(
        text: "Typed",
        rect: CanvasRect(x: 15, y: 60, width: 120, height: 25),
        confidence: 1,
        source: .typed
    )
    let original = RecognizedNoteText(
        schemaVersion: RecognizedNoteText.currentSchemaVersion,
        inputFingerprint: "abc123",
        generatedAt: Date(timeIntervalSince1970: 1_234),
        pages: [
            RecognizedPageText(
                pageID: pageID,
                pageIndex: 0,
                lines: [inkLine, typedLine],
                plainText: "Written\nTyped"
            )
        ]
    )

    let data = try VellumJSONCoding.encoder().encode(original)
    let decoded = try VellumJSONCoding.decoder().decode(RecognizedNoteText.self, from: data)

    #expect(decoded == original)
}

@Test("Missing recognized note fields decode with tolerant defaults")
func recognizedNoteTextTolerantDecoding() throws {
    let data = Data("{}".utf8)

    let decoded = try VellumJSONCoding.decoder().decode(RecognizedNoteText.self, from: data)

    #expect(decoded.schemaVersion == RecognizedNoteText.currentSchemaVersion)
    #expect(decoded.inputFingerprint.isEmpty)
    #expect(decoded.generatedAt == Date(timeIntervalSince1970: 0))
    #expect(decoded.pages.isEmpty)
}
