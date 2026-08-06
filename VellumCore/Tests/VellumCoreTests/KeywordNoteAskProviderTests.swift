import Foundation
import Testing
@testable import VellumCore

@Test("Keyword stream emits citations, cumulative partials, then done")
func keywordStreamEventOrderAndCumulativePartials() async throws {
    let sparsePageID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let densePageID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let source = makeKeywordSource(pages: [
        AskPage(pageID: sparsePageID, plainText: "Comet appears once."),
        AskPage(pageID: densePageID, plainText: "Comet comet comet fills the sky."),
    ])
    let session = await KeywordNoteAskProvider().makeSession(source: source)

    let events = try await collectEvents(from: session.ask("Tell me about comet"))

    guard case .citations(let citations) = try #require(events.first) else {
        Issue.record("Expected citations to be the first event")
        return
    }
    #expect(citations.map(\.pageID) == [densePageID, sparsePageID])
    #expect(citations.map(\.index) == [1, 2])
    #expect(events.last == .done)

    let partials = events.compactMap { event -> String? in
        guard case .partial(let text) = event else { return nil }
        return text
    }
    #expect(partials.count == 3)
    #expect(zip(partials, partials.dropFirst()).allSatisfy { previous, next in
        next.hasPrefix(previous) && next.count > previous.count
    })
    #expect(events.dropFirst().dropLast().allSatisfy {
        if case .partial = $0 { return true }
        return false
    })
}

@Test("Keyword citations cap matching pages at three with deterministic ties")
func keywordCitationRankingAndLimit() async throws {
    let pageIDs = try [
        "00000000-0000-0000-0000-000000000004",
        "00000000-0000-0000-0000-000000000002",
        "00000000-0000-0000-0000-000000000003",
        "00000000-0000-0000-0000-000000000001",
    ].map { try #require(UUID(uuidString: $0)) }
    let source = makeKeywordSource(
        pages: pageIDs.map { AskPage(pageID: $0, plainText: "Quartz appears here.") }
    )
    let session = await KeywordNoteAskProvider().makeSession(source: source)

    let events = try await collectEvents(from: session.ask("quartz"))
    guard case .citations(let citations) = try #require(events.first) else {
        Issue.record("Expected citations to be the first event")
        return
    }

    #expect(citations.map(\.pageID) == [pageIDs[3], pageIDs[1], pageIDs[2]])
    #expect(citations.count == 3)
}

@Test("No-match stream omits citations and returns the fixed response")
func keywordNoMatchStream() async throws {
    let source = makeKeywordSource(pages: [
        AskPage(pageID: UUID(), plainText: "What is this text?")
    ])
    let session = await KeywordNoteAskProvider().makeSession(source: source)

    let events = try await collectEvents(from: session.ask("What is this?"))

    #expect(events == [
        .partial("I couldn't find anything about that in this note."),
        .done,
    ])
}

@Test("Summary uses the first three non-empty sentences across pages")
func keywordSummaryUsesFirstThreeSentences() async throws {
    let source = makeKeywordSource(pages: [
        AskPage(pageID: UUID(), plainText: "First sentence. Second sentence!"),
        AskPage(pageID: UUID(), plainText: "Third sentence? Fourth sentence."),
    ])
    let session = await KeywordNoteAskProvider().makeSession(source: source)

    #expect(try await session.summarize() == "First sentence. Second sentence. Third sentence.")
}

@Test("Summary documents the empty-note response")
func keywordEmptySummary() async throws {
    let source = makeKeywordSource(pages: [
        AskPage(pageID: UUID(), plainText: ""),
        AskPage(pageID: UUID(), plainText: "  \n  "),
    ])
    let session = await KeywordNoteAskProvider().makeSession(source: source)

    #expect(try await session.summarize() == "This note is empty.")
}

@Test("Provider reports available and fallback states")
func keywordProviderAvailability() async {
    #expect(await KeywordNoteAskProvider().availability() == .available)
    #expect(
        await KeywordNoteAskProvider(asFallback: true).availability()
            == .fallback(reason: "Apple Intelligence is unavailable")
    )
    #expect(
        await KeywordNoteAskProvider(
            asFallback: true,
            fallbackReason: "Model is offline"
        ).availability() == .fallback(reason: "Model is offline")
    )
}

@Test("Note ask turns expose streaming-friendly defaults")
func noteAskTurnDefaults() throws {
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
    let turn = NoteAskTurn(id: id, question: "What is here?")

    #expect(turn.id == id)
    #expect(turn.question == "What is here?")
    #expect(turn.answerText.isEmpty)
    #expect(turn.citations.isEmpty)
    #expect(!turn.isComplete)
}

private func collectEvents(
    from stream: AsyncThrowingStream<NoteAskStreamEvent, Error>
) async throws -> [NoteAskStreamEvent] {
    var events: [NoteAskStreamEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

private func makeKeywordSource(pages: [AskPage]) -> AskSource {
    AskSource(
        noteID: UUID(),
        title: "Keyword Note",
        noteType: .note,
        pages: pages
    )
}
