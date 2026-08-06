import Foundation
@testable import Vellum
import VellumCore
import XCTest

private actor ScriptedInkRecognizer: InkTextRecognizing {
    private var lines: [RecognizedLine]
    private let delay: Duration
    private var callCount = 0
    private var completionCount = 0

    init(lines: [RecognizedLine], delay: Duration = .zero) {
        self.lines = lines
        self.delay = delay
    }

    func recognizeInk(
        drawingData: Data?,
        geometry: PageGeometry,
        bandCount: Int
    ) async throws -> [RecognizedLine] {
        callCount += 1
        let result = lines
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()
        completionCount += 1
        return result
    }

    func setLines(_ lines: [RecognizedLine]) {
        self.lines = lines
    }

    func numberOfCalls() -> Int {
        callCount
    }

    func numberOfCompletions() -> Int {
        completionCount
    }
}

@MainActor
private final class RecordingRecognitionApplier: RecognitionApplying {
    var input: TextRecognitionInput?
    private(set) var outcomes: [TextRecognitionOutcome] = []

    init(input: TextRecognitionInput?) {
        self.input = input
    }

    func currentRecognitionInput() -> TextRecognitionInput? {
        input
    }

    func applyRecognitionOutcome(_ outcome: TextRecognitionOutcome) {
        outcomes.append(outcome)
    }
}

@MainActor
final class NoteTextRecognitionCoordinatorTests: XCTestCase {
    private var rootDirectory: URL!
    private var container: AppContainer!

    override func setUp() async throws {
        try await super.setUp()
        rootDirectory = try TemporaryDirectory.make()
        container = AppContainer.live(rootDirectory: rootDirectory)
    }

    override func tearDown() async throws {
        container = nil
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        rootDirectory = nil
        try await super.tearDown()
    }

    func testRapidSavesPerformOneRecognition() async throws {
        let recognizer = ScriptedInkRecognizer(lines: [line("Latest result")])
        let coordinator = makeCoordinator(recognizer: recognizer)
        let note = try await container.workspace.createNote(title: "Untitled")
        let input = TextRecognitionInput(note: note, drawingData: nil)

        coordinator.noteDidSave(input)
        coordinator.noteDidSave(input)

        let didRecognize = try await waitUntil {
            await recognizer.numberOfCalls() == 1
        }
        let callCountStayedAtOne = try await callCountRemains(1, recognizer: recognizer)
        XCTAssertTrue(didRecognize)
        XCTAssertTrue(callCountStayedAtOne)
    }

    func testCompletedFingerprintSkipsIdenticalInput() async throws {
        let recognizer = ScriptedInkRecognizer(lines: [line("Recognized once")])
        let coordinator = makeCoordinator(recognizer: recognizer)
        let note = try await container.workspace.createNote(title: "Untitled")
        let input = TextRecognitionInput(note: note, drawingData: nil)

        coordinator.noteDidSave(input)
        let didWriteSidecar = try await waitUntil {
            try await self.container.notes.loadAsset(
                noteID: note.id,
                relativePath: RecognitionSidecar.relativePath
            ) != nil
        }
        let initialCallCountStayedAtOne = try await callCountRemains(
            1,
            recognizer: recognizer
        )
        XCTAssertTrue(didWriteSidecar)
        XCTAssertTrue(initialCallCountStayedAtOne)

        coordinator.noteDidSave(input)

        let repeatedCallCountStayedAtOne = try await callCountRemains(
            1,
            recognizer: recognizer
        )
        XCTAssertTrue(repeatedCallCountStayedAtOne)
    }

    func testClosedNotePersistsRecognitionSidecarAndAutomaticTitle() async throws {
        let recognizedText = "Meeting notes. Follow up"
        let typedText = "Typed context"
        let recognizer = ScriptedInkRecognizer(lines: [line(recognizedText)])
        let coordinator = makeCoordinator(recognizer: recognizer)
        let note = try await saveNote(
            title: "Untitled",
            titleOrigin: .default,
            typedTexts: [typedText]
        )
        let input = TextRecognitionInput(note: note, drawingData: nil)
        let expectedPageText = "\(recognizedText)\n\(typedText)"

        coordinator.noteDidSave(input)

        let didApply = try await waitUntil {
            let reloaded = try await self.container.workspace.loadNote(id: note.id)
            let sidecar = try await self.container.notes.loadAsset(
                noteID: note.id,
                relativePath: RecognitionSidecar.relativePath
            )
            return reloaded.pages[0].plainText == expectedPageText
                && reloaded.title == "Meeting notes"
                && sidecar != nil
        }
        XCTAssertTrue(didApply)

        let reloaded = try await container.workspace.loadNote(id: note.id)
        XCTAssertEqual(reloaded.pages[0].plainText, expectedPageText)
        XCTAssertEqual(reloaded.title, "Meeting notes")
        XCTAssertEqual(reloaded.titleOrigin, .auto)

        let loadedSidecarData = try await container.notes.loadAsset(
            noteID: note.id,
            relativePath: RecognitionSidecar.relativePath
        )
        let sidecarData = try XCTUnwrap(loadedSidecarData)
        let sidecar = try VellumJSONCoding.decoder().decode(
            RecognizedNoteText.self,
            from: sidecarData
        )
        XCTAssertEqual(
            sidecar.inputFingerprint,
            TextRecognitionService.fingerprint(for: input)
        )
    }

    func testSidecarWithUnpersistedPageTextRerunsRecognition() async throws {
        let recognizedText = "Recovered recognition"
        let typedText = "Original source"
        let expectedPageText = "\(recognizedText)\n\(typedText)"
        let recognizer = ScriptedInkRecognizer(lines: [line(recognizedText)])
        let coordinator = makeCoordinator(recognizer: recognizer)
        let note = try await saveNote(
            title: "Untitled",
            titleOrigin: .default,
            typedTexts: [typedText]
        )

        coordinator.noteDidSave(TextRecognitionInput(note: note, drawingData: nil))

        let didInitiallyApply = try await waitUntil {
            let reloaded = try await self.container.workspace.loadNote(id: note.id)
            let sidecar = try await self.container.notes.loadAsset(
                noteID: note.id,
                relativePath: RecognitionSidecar.relativePath
            )
            return reloaded.pages[0].plainText == expectedPageText && sidecar != nil
        }
        XCTAssertTrue(didInitiallyApply)
        let initialCallCount = await recognizer.numberOfCalls()
        let initialCompletionCount = await recognizer.numberOfCompletions()
        XCTAssertEqual(initialCallCount, 1)
        XCTAssertEqual(initialCompletionCount, 1)

        var resetNote = try await container.workspace.loadNote(id: note.id)
        resetNote.pages[0].plainText = ""
        _ = try await container.workspace.saveNote(resetNote)
        let blankedNote = try await container.workspace.loadNote(id: note.id)

        let freshCoordinator = makeCoordinator(recognizer: recognizer)
        freshCoordinator.noteDidSave(
            TextRecognitionInput(note: blankedNote, drawingData: nil)
        )

        let didRecognizeAgain = try await waitUntil {
            await recognizer.numberOfCalls() == 2
        }
        let didSelfHeal = try await waitUntil {
            let reloaded = try await self.container.workspace.loadNote(id: note.id)
            return reloaded.pages[0].plainText == expectedPageText
        }
        XCTAssertTrue(didRecognizeAgain)
        XCTAssertTrue(didSelfHeal)
    }

    func testClosedNotePreservesManualTitle() async throws {
        let recognizer = ScriptedInkRecognizer(lines: [line("Suggested title. Details")])
        let coordinator = makeCoordinator(recognizer: recognizer)
        let note = try await saveNote(
            title: "My title",
            titleOrigin: .manual,
            typedTexts: []
        )

        coordinator.noteDidSave(TextRecognitionInput(note: note, drawingData: nil))

        let didApply = try await waitUntil {
            let reloaded = try await self.container.workspace.loadNote(id: note.id)
            return reloaded.pages[0].plainText == "Suggested title. Details"
        }
        XCTAssertTrue(didApply)
        let reloaded = try await container.workspace.loadNote(id: note.id)
        XCTAssertEqual(reloaded.title, "My title")
        XCTAssertEqual(reloaded.titleOrigin, .manual)
    }

    func testClosedNoteDropsStaleOutcomeWithoutClobberingNewerSave() async throws {
        let recognizer = ScriptedInkRecognizer(
            lines: [line("Stale recognition")],
            delay: .milliseconds(100)
        )
        let coordinator = makeCoordinator(recognizer: recognizer)
        let original = try await saveNote(
            title: "Manual title",
            titleOrigin: .manual,
            typedTexts: ["Original source"]
        )
        coordinator.noteDidSave(TextRecognitionInput(note: original, drawingData: nil))
        let didStartRecognition = try await waitUntil {
            await recognizer.numberOfCalls() == 1
        }
        XCTAssertTrue(didStartRecognition)

        var newerNote = try await container.workspace.loadNote(id: original.id)
        newerNote.pages[0].elements.append(textElement("Newer source", y: 160))
        let persistedMutation = try await container.workspace.saveNote(newerNote)

        let didCompleteRecognition = try await waitUntil {
            await recognizer.numberOfCompletions() == 1
        }
        let callCountStayedAtOne = try await callCountRemains(1, recognizer: recognizer)
        XCTAssertTrue(didCompleteRecognition)
        XCTAssertTrue(callCountStayedAtOne)

        let reloaded = try await container.workspace.loadNote(id: original.id)
        XCTAssertEqual(reloaded.revision, persistedMutation.revision)
        // Compare identities, not full Equatable: element createdAt dates lose
        // sub-millisecond precision through the JSON round trip.
        XCTAssertEqual(
            reloaded.pages[0].elements.map(\.id),
            persistedMutation.pages[0].elements.map(\.id)
        )
        XCTAssertFalse(reloaded.pages[0].plainText.contains("Stale recognition"))
        let sidecar = try await container.notes.loadAsset(
            noteID: original.id,
            relativePath: RecognitionSidecar.relativePath
        )
        XCTAssertNil(sidecar)
    }

    func testOpenNoteAppliesThroughRegisteredModelWithoutSavingManifest() async throws {
        let recognizer = ScriptedInkRecognizer(lines: [line("Open result")])
        let coordinator = makeCoordinator(recognizer: recognizer)
        let note = try await container.workspace.createNote(title: "Open note")
        let input = TextRecognitionInput(note: note, drawingData: nil)
        let applier = RecordingRecognitionApplier(input: input)
        coordinator.register(applier, noteID: note.id)
        let revisionBeforeRecognition = try await container.workspace.loadNote(id: note.id).revision

        coordinator.noteDidSave(input)

        let didApplyToOpenNote = try await waitUntil {
            applier.outcomes.count == 1
        }
        let didWriteSidecar = try await waitUntil {
            try await self.container.notes.loadAsset(
                noteID: note.id,
                relativePath: RecognitionSidecar.relativePath
            ) != nil
        }
        XCTAssertTrue(didApplyToOpenNote)
        XCTAssertTrue(didWriteSidecar)

        let outcome = try XCTUnwrap(applier.outcomes.first)
        XCTAssertEqual(outcome.pageTexts, [note.pages[0].id: "Open result"])
        XCTAssertEqual(outcome.fingerprint, TextRecognitionService.fingerprint(for: input))
        XCTAssertEqual(applier.outcomes.count, 1)
        let revisionAfterRecognition = try await container.workspace.loadNote(id: note.id).revision
        XCTAssertEqual(revisionAfterRecognition, revisionBeforeRecognition)
    }

    func testUnregisteredNoteFallsBackToClosedPath() async throws {
        let recognizer = ScriptedInkRecognizer(lines: [line("Closed result")])
        let coordinator = makeCoordinator(recognizer: recognizer)
        let note = try await container.workspace.createNote(title: "Existing title")
        let input = TextRecognitionInput(note: note, drawingData: nil)
        let applier = RecordingRecognitionApplier(input: input)
        coordinator.register(applier, noteID: note.id)
        coordinator.unregister(noteID: note.id)

        coordinator.noteDidSave(input)

        let didApplyToClosedNote = try await waitUntil {
            let reloaded = try await self.container.workspace.loadNote(id: note.id)
            let sidecar = try await self.container.notes.loadAsset(
                noteID: note.id,
                relativePath: RecognitionSidecar.relativePath
            )
            return reloaded.pages[0].plainText == "Closed result" && sidecar != nil
        }
        XCTAssertTrue(didApplyToClosedNote)
        XCTAssertTrue(applier.outcomes.isEmpty)
        let sidecar = try await container.notes.loadAsset(
            noteID: note.id,
            relativePath: RecognitionSidecar.relativePath
        )
        XCTAssertNotNil(sidecar)
    }

    private func makeCoordinator(
        recognizer: ScriptedInkRecognizer
    ) -> NoteTextRecognitionCoordinator {
        NoteTextRecognitionCoordinator(
            service: TextRecognitionService(recognizer: recognizer),
            workspace: container.workspace,
            notes: container.notes,
            debounce: .milliseconds(10)
        )
    }

    private func saveNote(
        title: String,
        titleOrigin: TitleOrigin,
        typedTexts: [String]
    ) async throws -> Note {
        var note = try await container.workspace.createNote(title: title)
        note.titleOrigin = titleOrigin
        note.pages[0].elements = typedTexts.enumerated().map { index, text in
            textElement(text, y: 100 + Double(index * 60))
        }
        return try await container.workspace.saveNote(note)
    }

    private func line(_ text: String) -> RecognizedLine {
        RecognizedLine(
            text: text,
            rect: CanvasRect(x: 10, y: 20, width: 200, height: 30),
            confidence: 0.95,
            source: .ink
        )
    }

    private func textElement(_ text: String, y: Double) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: text,
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: CanvasRect(x: 10, y: y, width: 200, height: 40)
        )
    }

    private func waitUntil(
        _ condition: @MainActor () async throws -> Bool
    ) async throws -> Bool {
        for _ in 0..<300 {
            if try await condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func callCountRemains(
        _ expectedCount: Int,
        recognizer: ScriptedInkRecognizer
    ) async throws -> Bool {
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(10))
            guard await recognizer.numberOfCalls() == expectedCount else {
                return false
            }
        }
        return true
    }
}
