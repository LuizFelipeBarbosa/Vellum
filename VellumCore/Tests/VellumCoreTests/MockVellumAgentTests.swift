import Foundation
import Testing
@testable import VellumCore

@Test("Empty text has no proposals")
func mockAgentEmptyText() async throws {
    let proposals = try await analyze(text: "  \n", title: "Untitled")
    #expect(proposals.isEmpty)
}

@Test("TODO creates a task tag proposal")
func mockAgentTodoRule() async throws {
    let proposals = try await analyze(text: "TODO call the client", title: "Plan")
    #expect(proposals.map(\.operation) == [
        .addTag("task"),
        .extractTask(text: "TODO call the client", pageID: nil),
    ])
    #expect(proposals[0].confidence == 0.9)
    #expect(proposals[0].explanation.contains("TODO"))
}

@Test("Untitled notes receive a first-sentence title")
func mockAgentTitleRule() async throws {
    let proposals = try await analyze(
        text: "A concise first sentence. A second sentence.",
        title: "Untitled"
    )
    #expect(proposals.map(\.operation) == [.suggestTitle("A concise first sentence")])
}

@Test("Long text receives a capped summary")
func mockAgentSummaryRule() async throws {
    let text = String(repeating: "abcdefghij", count: 25)
    let proposals = try await analyze(text: text, title: "Long note")
    #expect(proposals.map(\.operation) == [.createSummary(String(text.prefix(200)))])
    #expect(proposals[0].confidence == 0.6)
}

@Test("Mock proposals retain task, title, summary ordering")
func mockAgentOrdering() async throws {
    let text = "TODO " + String(repeating: "ordered content ", count: 10)
    let proposals = try await analyze(text: text, title: "Untitled")

    #expect(proposals.count == 4)
    #expect(proposals[0].operation == .addTag("task"))
    if case .suggestTitle(let title) = proposals[1].operation {
        #expect(title == String(text.prefix(60)))
    } else {
        Issue.record("The second operation should suggest a title.")
    }
    if case .createSummary(let summary) = proposals[2].operation {
        #expect(summary == text.trimmingCharacters(in: .whitespacesAndNewlines))
    } else {
        Issue.record("The third operation should create a summary.")
    }
    #expect(proposals[3].operation == .extractTask(
        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
        pageID: nil
    ))
}

@Test("Space heuristic files an unfiled matching note")
func mockAgentSpaceRule() async throws {
    let space = Space(id: UUID(), name: "Research", color: .purple, createdAt: Date())
    let proposals = try await analyze(text: "research findings", title: "Plan", spaces: [space])
    #expect(proposals.map(\.operation) == [.fileToSpace(spaceName: "Research", color: .purple)])
}

@Test("Space heuristic abstains for an already filed note")
func mockAgentSpaceAbstains() async throws {
    let space = Space(id: UUID(), name: "Research", color: .purple, createdAt: Date())
    let proposals = try await analyze(
        text: "research findings",
        title: "Plan",
        currentSpaceID: UUID(),
        spaces: [space]
    )
    #expect(!proposals.contains { if case .fileToSpace = $0.operation { true } else { false } })
}

@Test("Link heuristic sorts candidates and caps at three")
func mockAgentLinkRule() async throws {
    let refs = ["Zulu Note", "Alpha Note", "Beta Note", "Gamma Note"].map {
        NoteRef(id: UUID(), title: $0)
    }
    let proposals = try await analyze(
        text: "Zulu Note Alpha Note Beta Note Gamma Note",
        title: "Links",
        otherNotes: refs
    )
    let linked = proposals.compactMap { proposal -> UUID? in
        if case .linkNotes(let id, .mention) = proposal.operation { return id }
        return nil
    }
    #expect(linked == refs.sorted { $0.title < $1.title }.prefix(3).map(\.id))
}

@Test("Link heuristic abstains for short or absent titles")
func mockAgentLinkAbstains() async throws {
    let refs = [NoteRef(id: UUID(), title: "ABC"), NoteRef(id: UUID(), title: "Missing")]
    let proposals = try await analyze(text: "ABC only", title: "Links", otherNotes: refs)
    #expect(!proposals.contains { if case .linkNotes = $0.operation { true } else { false } })
}

@Test("Task heuristic preserves matching line order")
func mockAgentExtractTaskRule() async throws {
    let text = "TODO first\nignore\n- [ ] second\nPlease FOLLOW UP tomorrow"
    let proposals = try await analyze(text: text, title: "Actions")
    let tasks = proposals.compactMap { proposal -> String? in
        if case .extractTask(let text, nil) = proposal.operation { return text }
        return nil
    }
    #expect(tasks == ["TODO first", "- [ ] second", "Please FOLLOW UP tomorrow"])
}

@Test("Task heuristic abstains without an action pattern")
func mockAgentExtractTaskAbstains() async throws {
    let proposals = try await analyze(text: "ordinary notes", title: "Actions")
    #expect(!proposals.contains { if case .extractTask = $0.operation { true } else { false } })
}

@Test("Entity heuristic deduplicates, sorts, and retains excerpts")
func mockAgentEntityRule() async throws {
    let text = "Zara Stone joined.\nI met Alice Brown today.\nAlice Brown returned."
    let proposals = try await analyze(text: text, title: "People")
    let entities = proposals.compactMap { proposal -> (String, String?)? in
        if case .extractEntity(let name, .person, nil, let excerpt) = proposal.operation {
            return (name, excerpt)
        }
        return nil
    }
    #expect(entities.map(\.0) == ["Alice Brown", "Zara Stone"])
    #expect(entities[0].1 == "I met Alice Brown today.")
}

@Test("Entity heuristic filters sentence-starter pairs")
func mockAgentEntityAbstains() async throws {
    let proposals = try await analyze(text: "This Morning was quiet.", title: "Journal")
    #expect(!proposals.contains { if case .extractEntity = $0.operation { true } else { false } })
}

private func analyze(
    text: String,
    title: String,
    currentSpaceID: UUID? = nil,
    spaces: [Space] = [],
    otherNotes: [NoteRef] = []
) async throws -> [AgentProposal] {
    let noteID = UUID()
    let event = WorkspaceEvent(
        id: UUID(),
        noteID: noteID,
        noteRevision: 4,
        createdAt: Date(timeIntervalSince1970: 1_000),
        kind: .analysisRequested
    )
    let context = AgentContext(
        noteID: noteID,
        noteRevision: 4,
        title: title,
        canonicalText: text,
        currentSpaceID: currentSpaceID,
        spaces: spaces,
        otherNotes: otherNotes
    )
    return try await MockVellumAgent().analyze(event: event, context: context)
}
