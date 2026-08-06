import CryptoKit
import Foundation

public struct TextRecognitionInput: Sendable {
    public let noteID: UUID
    public let drawingData: Data?
    public let pages: [NotePage]
    public let geometry: PageGeometry

    public init(note: Note, drawingData: Data?) {
        noteID = note.id
        self.drawingData = drawingData
        pages = note.pages.sorted(by: NotePage.byOrder)
        geometry = note.pageGeometry
    }
}

public struct TextRecognitionOutcome: Sendable {
    public let noteID: UUID
    public let fingerprint: String
    public let pageTexts: [UUID: String]
    public let document: RecognizedNoteText
}

public actor TextRecognitionService {
    private let recognizer: any InkTextRecognizing

    public init(recognizer: any InkTextRecognizing) {
        self.recognizer = recognizer
    }

    /// Fingerprints only source content: ink, typed elements, and page layout.
    /// Recognition output, note titles, and existing page plain text are excluded so
    /// applying recognition results cannot trigger an apply/save/re-recognize loop.
    public nonisolated static func fingerprint(for input: TextRecognitionInput) -> String {
        var hasher = SHA256()

        func update(_ data: Data) {
            var byteCount = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &byteCount) { hasher.update(bufferPointer: $0) }
            hasher.update(data: data)
        }

        func update(_ value: String) {
            update(Data(value.utf8))
        }

        if let drawingData = input.drawingData {
            update("drawing-data")
            update(drawingData)
        } else {
            update("nil-drawing")
        }

        for (pageIndex, page) in input.pages.enumerated() {
            update("page-\(pageIndex)")
            for element in page.elements {
                guard case .text(let box) = element.content else { continue }
                update("typed-text")
                update(box.text)
                update(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), element.frame.x))
                update(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), element.frame.y))
                update(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), element.frame.width))
                update(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), element.frame.height))
            }
        }

        update("page-count")
        update(String(input.pages.count))
        update("aspect-ratio")
        update(String(
            format: "%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            input.geometry.aspectRatio
        ))

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func recognize(_ input: TextRecognitionInput) async throws -> TextRecognitionOutcome {
        try Task.checkCancellation()
        let inkLines = try await recognizer.recognizeInk(
            drawingData: input.drawingData,
            geometry: input.geometry,
            bandCount: input.pages.count
        )
        try Task.checkCancellation()

        let recognizedPages = PageTextAssembler.assemble(
            inkLines: inkLines,
            pages: input.pages,
            geometry: input.geometry
        )
        let document = RecognizedNoteText(
            schemaVersion: RecognizedNoteText.currentSchemaVersion,
            inputFingerprint: Self.fingerprint(for: input),
            generatedAt: Date(),
            pages: recognizedPages
        )
        let pageTexts = Dictionary(
            recognizedPages.map { ($0.pageID, $0.plainText) },
            uniquingKeysWith: { _, latest in latest }
        )
        return TextRecognitionOutcome(
            noteID: input.noteID,
            fingerprint: document.inputFingerprint,
            pageTexts: pageTexts,
            document: document
        )
    }
}
