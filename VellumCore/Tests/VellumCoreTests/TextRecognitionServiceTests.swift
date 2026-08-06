import Foundation
import Testing
@testable import VellumCore

@Test("Recognition maps each page ID to its assembled plain text")
func textRecognitionServiceMapsPageTexts() async throws {
    let firstPageID = UUID()
    let secondPageID = UUID()
    let pages = [
        servicePage(id: firstPageID, order: 0),
        servicePage(id: secondPageID, order: 1),
    ]
    let note = serviceNote(pages: pages)
    let pageHeight = Double(note.pageGeometry.pageHeight)
    let recognizer = CannedInkRecognizer(lines: [
        serviceLine("First", y: 20),
        serviceLine("Second", y: pageHeight + 20),
    ])
    let service = TextRecognitionService(recognizer: recognizer)

    let outcome = try await service.recognize(
        TextRecognitionInput(note: note, drawingData: Data([1, 2, 3]))
    )

    #expect(outcome.noteID == note.id)
    #expect(outcome.pageTexts == [firstPageID: "First", secondPageID: "Second"])
    #expect(outcome.document.pages.map(\.pageID) == [firstPageID, secondPageID])
    #expect(outcome.fingerprint == outcome.document.inputFingerprint)
}

@Test("Fingerprints are stable for structurally identical inputs")
func textRecognitionFingerprintIsStable() {
    let page = servicePage(
        elements: [serviceTextElement("Same text", frame: CanvasRect(x: 1, y: 2, width: 3, height: 4))]
    )
    let note = serviceNote(pages: [page])
    let first = TextRecognitionInput(note: note, drawingData: Data([4, 5, 6]))
    let second = TextRecognitionInput(note: note, drawingData: Data([4, 5, 6]))

    #expect(
        TextRecognitionService.fingerprint(for: first)
            == TextRecognitionService.fingerprint(for: second)
    )
}

@Test("Fingerprint changes when drawing bytes change")
func textRecognitionFingerprintIncludesDrawingData() {
    let note = serviceNote(pages: [servicePage()])
    let first = TextRecognitionInput(note: note, drawingData: Data([1]))
    let second = TextRecognitionInput(note: note, drawingData: Data([2]))

    #expect(
        TextRecognitionService.fingerprint(for: first)
            != TextRecognitionService.fingerprint(for: second)
    )
}

@Test("Fingerprint changes when typed text changes")
func textRecognitionFingerprintIncludesTypedText() {
    let frame = CanvasRect(x: 1, y: 2, width: 100, height: 20)
    let firstNote = serviceNote(pages: [
        servicePage(elements: [serviceTextElement("Alpha", frame: frame)])
    ])
    let secondNote = serviceNote(pages: [
        servicePage(elements: [serviceTextElement("Beta", frame: frame)])
    ])

    #expect(
        fingerprint(firstNote) != fingerprint(secondNote)
    )
}

@Test("Fingerprint changes when a typed text frame changes")
func textRecognitionFingerprintIncludesTypedFrame() {
    let firstNote = serviceNote(pages: [
        servicePage(elements: [
            serviceTextElement("Text", frame: CanvasRect(x: 1, y: 2, width: 100, height: 20))
        ])
    ])
    let secondNote = serviceNote(pages: [
        servicePage(elements: [
            serviceTextElement("Text", frame: CanvasRect(x: 2, y: 2, width: 100, height: 20))
        ])
    ])

    #expect(
        fingerprint(firstNote) != fingerprint(secondNote)
    )
}

@Test("Fingerprint changes when page count changes")
func textRecognitionFingerprintIncludesPageCount() {
    let firstNote = serviceNote(pages: [servicePage(order: 0)])
    let secondNote = serviceNote(pages: [
        servicePage(order: 0),
        servicePage(order: 1),
    ])

    #expect(
        fingerprint(firstNote) != fingerprint(secondNote)
    )
}

@Test("Fingerprint changes when page aspect ratio changes")
func textRecognitionFingerprintIncludesGeometry() {
    let page = servicePage()
    let firstNote = serviceNote(pages: [page], pageAspectRatio: 1.0)
    let secondNote = serviceNote(pages: [page], pageAspectRatio: 2.0)

    #expect(
        fingerprint(firstNote) != fingerprint(secondNote)
    )
}

@Test("Fingerprint excludes note title and recognized page plain text")
func textRecognitionFingerprintExcludesRecognitionOutput() {
    let noteID = UUID()
    let pageID = UUID()
    let firstNote = serviceNote(
        id: noteID,
        title: "First title",
        pages: [servicePage(id: pageID, plainText: "First recognized output")]
    )
    let secondNote = serviceNote(
        id: noteID,
        title: "Second title",
        pages: [servicePage(id: pageID, plainText: "Different recognized output")]
    )

    #expect(
        fingerprint(firstNote) == fingerprint(secondNote)
    )
}

@Test("Nil drawing data is forwarded to the recognizer")
func textRecognitionServiceForwardsNilDrawingData() async throws {
    let recognizer = CannedInkRecognizer(lines: [])
    let service = TextRecognitionService(recognizer: recognizer)
    let input = TextRecognitionInput(
        note: serviceNote(pages: [servicePage()]),
        drawingData: nil
    )

    _ = try await service.recognize(input)

    #expect(await recognizer.lastCallHadNilDrawing())
}

private actor CannedInkRecognizer: InkTextRecognizing {
    private let lines: [RecognizedLine]
    private var drawingArguments: [Data?] = []

    init(lines: [RecognizedLine]) {
        self.lines = lines
    }

    func recognizeInk(
        drawingData: Data?,
        geometry: PageGeometry,
        bandCount: Int
    ) async throws -> [RecognizedLine] {
        drawingArguments.append(drawingData)
        return lines
    }

    func lastCallHadNilDrawing() -> Bool {
        guard let lastArgument = drawingArguments.last else { return false }
        return lastArgument == nil
    }
}

private func fingerprint(_ note: Note) -> String {
    TextRecognitionService.fingerprint(
        for: TextRecognitionInput(note: note, drawingData: Data([9, 8, 7]))
    )
}

private func serviceNote(
    id: UUID = UUID(),
    title: String = "Note",
    pages: [NotePage],
    pageAspectRatio: Double = PageLayout.a4AspectRatio
) -> Note {
    let timestamp = Date(timeIntervalSince1970: 100)
    return Note(
        id: id,
        schemaVersion: 1,
        revision: 1,
        title: title,
        tags: [],
        createdAt: timestamp,
        updatedAt: timestamp,
        pages: pages,
        pageAspectRatio: pageAspectRatio
    )
}

private func servicePage(
    id: UUID = UUID(),
    order: Int = 0,
    plainText: String = "",
    elements: [CanvasElement] = []
) -> NotePage {
    NotePage(
        id: id,
        order: order,
        plainText: plainText,
        drawingAssetPath: "drawing.data",
        background: .blank,
        elements: elements
    )
}

private func serviceLine(_ text: String, y: Double) -> RecognizedLine {
    RecognizedLine(
        text: text,
        rect: CanvasRect(x: 10, y: y, width: 100, height: 20),
        confidence: 0.95,
        source: .ink
    )
}

private func serviceTextElement(_ text: String, frame: CanvasRect) -> CanvasElement {
    CanvasElement(
        content: .text(
            TextBoxContent(
                text: text,
                fontSize: 16,
                color: CodableColor(red: 0, green: 0, blue: 0)
            )
        ),
        frame: frame
    )
}
