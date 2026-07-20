import Foundation
import Testing
@testable import VellumCore

@Test("A matching note produces an aligned citation")
func askSingleNoteMatch() async throws {
    let root = try makeAskTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let notes = FileNoteRepository(rootDirectory: root)
    var note = try await notes.createNote(title: "Weather")
    note.pages[0].plainText = "Ordinary introduction. Zephyr winds arrive every evening. Closing detail."
    try await notes.saveNote(note)
    let service = AskService(notes: notes, answerer: MockAskAnswerer(), activity: nil)

    let answer = try await service.ask("What do my notes say about zephyr?")

    let citation = try #require(answer.citations.first)
    #expect(answer.citations.count == 1)
    #expect(citation.noteID == note.id)
    #expect(citation.pageID == note.pages[0].id)
    #expect(citation.excerpt.contains("Zephyr winds arrive every evening"))
    let citationSegments = answer.segments.compactMap { segment -> Int? in
        if case .citation(let index) = segment { return index }
        return nil
    }
    #expect(citationSegments == [citation.index])
}

@Test("Trashed notes are excluded from Ask sources")
func askExcludesTrashedNotes() async throws {
    let root = try makeAskTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let notes = FileNoteRepository(rootDirectory: root)
    let workspace = WorkspaceService(
        notes: notes,
        proposals: FileProposalRepository(rootDirectory: root),
        activity: FileActivityRepository(rootDirectory: root),
        agent: MockVellumAgent(),
        spaces: FileSpaceRepository(rootDirectory: root),
        entities: FileEntityRepository(rootDirectory: root),
        tasks: FileTaskRepository(rootDirectory: root)
    )
    var active = try await workspace.createNote(title: "Active")
    active.pages[0].plainText = "Zephyr appears in this active note."
    try await notes.saveNote(active)
    var trashed = try await workspace.createNote(title: "Trashed")
    trashed.pages[0].plainText = "Zephyr appears in this trashed note."
    try await notes.saveNote(trashed)
    try await workspace.deleteNote(id: trashed.id)
    let service = AskService(notes: notes, answerer: MockAskAnswerer(), activity: nil)

    let answer = try await service.ask("What do my notes say about zephyr?")

    #expect(answer.citations.map(\.noteID) == [active.id])
    #expect(!answer.citations.contains { $0.noteID == trashed.id })
}

@Test("Multiple matching sources retain deterministic ranking and content")
func askRankingIsStable() async throws {
    let firstNoteID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let secondNoteID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let thirdNoteID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
    let context = AskContext(sources: [
        AskSource(
            noteID: firstNoteID,
            title: "Sparse",
            noteType: .note,
            pages: [AskPage(pageID: UUID(), plainText: "Comet appears once.")]
        ),
        AskSource(
            noteID: secondNoteID,
            title: "Dense",
            noteType: .pdf,
            pages: [AskPage(pageID: UUID(), plainText: "Comet comet comet fills this page.")]
        ),
        AskSource(
            noteID: thirdNoteID,
            title: "Medium",
            noteType: .deck,
            pages: [AskPage(pageID: UUID(), plainText: "Comet returns with another comet.")]
        ),
    ])
    let answerer = MockAskAnswerer()

    let first = try await answerer.answer(question: "Tell me about comet", context: context)
    let second = try await answerer.answer(question: "Tell me about comet", context: context)

    #expect(first.citations.map(\.index) == second.citations.map(\.index))
    #expect(first.citations.map(\.noteID) == second.citations.map(\.noteID))
    #expect(first.citations.map(\.pageID) == second.citations.map(\.pageID))
    #expect(first.citations.map(\.noteTitle) == second.citations.map(\.noteTitle))
    #expect(first.citations.map(\.noteType) == second.citations.map(\.noteType))
    #expect(first.citations.map(\.excerpt) == second.citations.map(\.excerpt))
    #expect(first.citations.map(\.noteID) == [secondNoteID, thirdNoteID, firstNoteID])
    #expect(first.segments == second.segments)
    #expect(first.followUps == second.followUps)
}

@Test("A stopword-only question returns the fixed no-match answer")
func askStopwordOnlyQuestion() async throws {
    let answer = try await MockAskAnswerer().answer(
        question: "What is this?",
        context: AskContext(
            sources: [
                AskSource(
                    noteID: UUID(),
                    title: "Question words",
                    noteType: .note,
                    pages: [AskPage(pageID: UUID(), plainText: "What is this text?")]
                )
            ]
        )
    )

    #expect(answer.citations.isEmpty)
    #expect(answer.followUps.isEmpty)
    #expect(answer.segments == [
        .text("I couldn't find anything about that in your notes.", emphasized: false)
    ])
}

@Test("An empty workspace returns the no-match answer")
func askEmptyWorkspace() async throws {
    let root = try makeAskTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = AskService(
        notes: FileNoteRepository(rootDirectory: root),
        answerer: MockAskAnswerer(),
        activity: nil
    )

    let answer = try await service.ask("Where is the zephyr?")

    #expect(answer.citations.isEmpty)
    #expect(answer.followUps.isEmpty)
    #expect(answer.segments == [
        .text("I couldn't find anything about that in your notes.", emphasized: false)
    ])
}

@Test("Asking logs activity only when a repository is supplied")
func askActivityLoggingIsOptional() async throws {
    let root = try makeAskTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let notes = FileNoteRepository(rootDirectory: root)
    let activity = FileActivityRepository(rootDirectory: root)
    let loggedService = AskService(
        notes: notes,
        answerer: MockAskAnswerer(),
        activity: activity
    )

    _ = try await loggedService.ask("Tell me about zephyr")

    let loggedEvents = try await activity.list(noteID: nil)
    #expect(loggedEvents.count == 1)
    #expect(loggedEvents[0].kind == .questionAnswered)
    #expect(loggedEvents[0].noteID == nil)

    let unloggedService = AskService(
        notes: notes,
        answerer: MockAskAnswerer(),
        activity: nil
    )
    _ = try await unloggedService.ask("Tell me about zephyr again")

    #expect(try await activity.list(noteID: nil).count == 1)
}

@Test("Suggested questions are recent-first, deterministic, and limited to three")
func suggestedQuestionsAreDeterministic() async throws {
    let root = try makeAskTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let notes = FileNoteRepository(rootDirectory: root)
    let titles = ["Oldest", "Newest", "Middle", "Fourth", "Empty"]
    let dates: [TimeInterval] = [1, 5, 3, 2, 6]
    for (title, date) in zip(titles, dates) {
        var note = try await notes.createNote(title: title)
        note.updatedAt = Date(timeIntervalSince1970: date)
        if title != "Empty" {
            note.pages[0].plainText = "Qualifying text"
        }
        try await notes.saveNote(note)
    }
    let service = AskService(notes: notes, answerer: MockAskAnswerer(), activity: nil)

    let first = try await service.suggestedQuestions()
    let second = try await service.suggestedQuestions()

    #expect(first == second)
    #expect(first.count <= 3)
    #expect(first == [
        "What do my notes say about Newest?",
        "What do my notes say about Middle?",
        "What do my notes say about Fourth?",
    ])
}

@Test("The excerpt uses the sentence with the strongest query match")
func askExcerptSelectsMatchingSentence() async throws {
    let matchingSentence = "Quartz details include quartz and another quartz reference"
    let context = AskContext(
        sources: [
            AskSource(
                noteID: UUID(),
                title: "Minerals",
                noteType: .note,
                pages: [
                    AskPage(
                        pageID: UUID(),
                        plainText: "Unrelated opening sentence. \(matchingSentence)! Unrelated ending sentence."
                    )
                ]
            )
        ]
    )

    let answer = try await MockAskAnswerer().answer(question: "What about quartz?", context: context)
    let excerpt = try #require(answer.citations.first?.excerpt)

    #expect(excerpt == matchingSentence)
    #expect(!excerpt.contains("Unrelated opening"))
    #expect(!excerpt.contains("Unrelated ending"))
}

private func makeAskTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("VellumCoreAskTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
