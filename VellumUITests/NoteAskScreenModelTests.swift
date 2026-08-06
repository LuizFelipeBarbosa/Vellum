import XCTest
@testable import Vellum
import VellumCore
import Foundation
import Synchronization

@MainActor
final class NoteAskScreenModelTests: XCTestCase {
    func testTurnAssemblyReplacesCumulativePartialText() async throws {
        let note = makeNote()
        let session = ScriptedNoteAskSession()
        let provider = ScriptedNoteAskProvider(session: session)
        let model = NoteAskScreenModel(note: note, provider: provider)
        await model.start()

        let contentPage = try XCTUnwrap(note.pages.first(where: {
            !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }))
        let source = try XCTUnwrap(provider.capturedSource())
        XCTAssertEqual(source.pages.map(\.pageID), [contentPage.id])

        let citations = [makeCitation(note: note, pageID: contentPage.id)]
        model.inputText = "What is the decision?"
        model.ask()
        let didStart = await waitUntil { session.askCallCount == 1 }
        XCTAssertTrue(didStart)

        session.yield(.citations(citations))
        session.yield(.partial("The first cumulative answer"))
        session.yield(.partial("The final cumulative answer"))
        session.yield(.done)
        session.finish()

        let didComplete = await waitUntil { model.phase == .idle }
        XCTAssertTrue(didComplete)
        let turn = try XCTUnwrap(model.turns.first)
        XCTAssertEqual(turn.answerText, "The final cumulative answer")
        XCTAssertEqual(turn.citations, citations)
        XCTAssertTrue(turn.isComplete)
    }

    func testCancellationMidStreamLeavesTurnIncompleteAndPhaseStreaming() async throws {
        let note = makeNote()
        let session = ScriptedNoteAskSession()
        let model = NoteAskScreenModel(
            note: note,
            provider: ScriptedNoteAskProvider(session: session)
        )
        await model.start()

        let contentPageID = try XCTUnwrap(note.pages.first(where: {
            !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.id)
        let citations = [makeCitation(note: note, pageID: contentPageID)]
        model.inputText = "What is here?"
        model.ask()
        let didStart = await waitUntil { session.askCallCount == 1 }
        XCTAssertTrue(didStart)

        session.yield(.citations(citations))
        let didReceiveCitations = await waitUntil {
            model.turns.first?.citations == citations
        }
        XCTAssertTrue(didReceiveCitations)
        model.cancel()
        await Task.yield()

        let turn = try XCTUnwrap(model.turns.first)
        XCTAssertFalse(turn.isComplete)
        XCTAssertEqual(model.phase, .streaming)
        session.finish()
    }

    func testStreamErrorCompletesTurnAndRetainsPartialText() async throws {
        let note = makeNote()
        let session = ScriptedNoteAskSession()
        let model = NoteAskScreenModel(
            note: note,
            provider: ScriptedNoteAskProvider(session: session)
        )
        await model.start()

        model.inputText = "What failed?"
        model.ask()
        let didStart = await waitUntil { session.askCallCount == 1 }
        XCTAssertTrue(didStart)

        session.yield(.partial("Answer before failure"))
        let didReceivePartial = await waitUntil {
            model.turns.first?.answerText == "Answer before failure"
        }
        XCTAssertTrue(didReceivePartial)
        session.finish(throwing: TestFailure(message: "stream failed"))

        let didFail = await waitUntil {
            model.phase == .error("stream failed")
        }
        XCTAssertTrue(didFail)
        let turn = try XCTUnwrap(model.turns.first)
        XCTAssertEqual(turn.answerText, "Answer before failure")
        XCTAssertTrue(turn.isComplete)
    }

    func testStartPublishesFallbackAvailability() async {
        let model = NoteAskScreenModel(
            note: makeNote(),
            provider: ScriptedNoteAskProvider(
                availability: .fallback(reason: "no model"),
                session: ScriptedNoteAskSession()
            )
        )

        await model.start()

        XCTAssertEqual(model.availability, .fallback(reason: "no model"))
    }

    func testSummarizeSetsSummaryOnSuccess() async {
        let session = ScriptedNoteAskSession(summary: .success("A short summary."))
        let model = NoteAskScreenModel(
            note: makeNote(),
            provider: ScriptedNoteAskProvider(session: session)
        )
        await model.start()

        model.summarize()

        let didSummarize = await waitUntil { model.summary == "A short summary." }
        XCTAssertTrue(didSummarize)
        XCTAssertEqual(model.phase, .idle)
    }

    func testWhitespaceQuestionIsNoOp() async {
        let session = ScriptedNoteAskSession()
        let model = NoteAskScreenModel(
            note: makeNote(),
            provider: ScriptedNoteAskProvider(session: session)
        )
        await model.start()

        model.inputText = "  \n  "
        model.ask()
        await Task.yield()

        XCTAssertTrue(model.turns.isEmpty)
        XCTAssertEqual(session.askCallCount, 0)
        XCTAssertEqual(model.phase, .idle)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func makeNote() -> Note {
        let noteID = UUID()
        let contentPageID = UUID()
        let blankPageID = UUID()
        let now = Date()
        return Note(
            id: noteID,
            schemaVersion: Note.currentSchemaVersion,
            revision: 1,
            title: "Project decisions",
            tags: [],
            createdAt: now,
            updatedAt: now,
            pages: [
                NotePage(
                    id: contentPageID,
                    order: 1,
                    plainText: "Use the steel beam after the engineer signs off.",
                    drawingAssetPath: "pages/\(contentPageID.uuidString)/drawing.data",
                    background: .blank
                ),
                NotePage(
                    id: blankPageID,
                    order: 0,
                    plainText: "  \n  ",
                    drawingAssetPath: "pages/\(blankPageID.uuidString)/drawing.data",
                    background: .blank
                ),
            ]
        )
    }

    private func makeCitation(note: Note, pageID: UUID) -> Citation {
        Citation(
            id: UUID(),
            index: 1,
            noteID: note.id,
            pageID: pageID,
            noteTitle: note.title,
            noteType: note.noteType,
            excerpt: "Use the steel beam."
        )
    }
}

private final class ScriptedNoteAskProvider: NoteAskProviding, Sendable {
    private let configuredAvailability: NoteAskAvailability
    private let session: ScriptedNoteAskSession
    private let source = Mutex<AskSource?>(nil)

    init(
        availability: NoteAskAvailability = .available,
        session: ScriptedNoteAskSession
    ) {
        configuredAvailability = availability
        self.session = session
    }

    func availability() async -> NoteAskAvailability {
        configuredAvailability
    }

    func makeSession(source: AskSource) async -> any NoteAskSession {
        self.source.withLock { $0 = source }
        return session
    }

    func capturedSource() -> AskSource? {
        source.withLock { $0 }
    }
}

private final class ScriptedNoteAskSession: NoteAskSession, Sendable {
    enum Summary: Sendable {
        case success(String)
        case failure(TestFailure)
    }

    private struct StreamState {
        var askCallCount = 0
        var continuation: AsyncThrowingStream<NoteAskStreamEvent, Error>.Continuation?
    }

    private let summary: Summary
    private let streamState = Mutex(StreamState())

    init(summary: Summary = .success("Summary")) {
        self.summary = summary
    }

    var askCallCount: Int {
        streamState.withLock { $0.askCallCount }
    }

    func ask(_ question: String) -> AsyncThrowingStream<NoteAskStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            streamState.withLock { state in
                state.askCallCount += 1
                state.continuation = continuation
            }
        }
    }

    func summarize() async throws -> String {
        switch summary {
        case .success(let text):
            text
        case .failure(let error):
            throw error
        }
    }

    func yield(_ event: NoteAskStreamEvent) {
        streamState.withLock { $0.continuation }?.yield(event)
    }

    func finish(throwing error: Error? = nil) {
        let continuation = streamState.withLock { state in
            defer { state.continuation = nil }
            return state.continuation
        }
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
    }
}

private struct TestFailure: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}
