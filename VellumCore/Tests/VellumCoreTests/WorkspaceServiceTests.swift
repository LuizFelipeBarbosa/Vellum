import Foundation
import Testing
@testable import VellumCore

@Test("Analysis stores deterministic mock proposals")
func analysisStoresProposals() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    var note = try await fixture.service.createNote(title: "Work")
    note.pages[0].plainText = "TODO " + String(repeating: "This is a substantial task description. ", count: 4)
    try await fixture.notes.saveNote(note)

    let generated = try await fixture.service.requestAnalysis(noteID: note.id)
    let stored = try await fixture.service.listProposals(noteID: note.id)

    #expect(generated.count == 3)
    #expect(Set(stored.map(\.id)) == Set(generated.map(\.id)))
    let text = note.pages[0].plainText
    let summary = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    #expect(stored.contains { $0.operation == .addTag("task") })
    #expect(stored.contains { $0.operation == .createSummary(summary) })
}

@Test("Accepting a title proposal changes title and revision")
func acceptTitleProposal() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    var note = try await fixture.service.createNote(title: "")
    note.pages[0].plainText = "A focused new title. More details follow."
    try await fixture.notes.saveNote(note)

    let generated = try await fixture.service.requestAnalysis(noteID: note.id)
    let titleProposal = try #require(generated.first { proposal in
        if case .suggestTitle = proposal.operation { return true }
        return false
    })
    let accepted = try await fixture.service.acceptProposal(id: titleProposal.id)

    #expect(accepted.title == "A focused new title")
    #expect(accepted.revision == note.revision + 1)
    #expect(try await fixture.service.loadNote(id: note.id).title == "A focused new title")
    let activity = try await fixture.service.activity(noteID: note.id)
    #expect(activity.contains { $0.kind.rawValue == ActivityKind.proposalAccepted.rawValue })
}

@Test("Rejecting a proposal preserves the note manifest")
func rejectProposalPreservesNote() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    var note = try await fixture.service.createNote(title: "Keep this")
    note.pages[0].plainText = "TODO keep every byte of user content."
    try await fixture.notes.saveNote(note)
    let proposal = try #require(
        try await fixture.service.requestAnalysis(noteID: note.id).first
    )
    let manifest = fixture.root
        .appendingPathComponent("\(note.id.uuidString).native-note")
        .appendingPathComponent("manifest.json")
    let before = try Data(contentsOf: manifest)

    try await fixture.service.rejectProposal(id: proposal.id)

    let after = try Data(contentsOf: manifest)
    #expect(after == before)
    #expect(try await fixture.service.loadNote(id: note.id).pages[0].plainText == note.pages[0].plainText)
    let activity = try await fixture.service.activity(noteID: note.id)
    #expect(activity.contains { $0.kind.rawValue == ActivityKind.proposalRejected.rawValue })
}

@Test("An old proposal becomes stale after the note changes")
func staleProposalCannotBeAccepted() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    var note = try await fixture.service.createNote(title: "Tasks")
    note.pages[0].plainText = "TODO revise this."
    try await fixture.notes.saveNote(note)
    let proposal = try #require(
        try await fixture.service.requestAnalysis(noteID: note.id).first
    )
    note.pages[0].plainText += " Changed later."
    _ = try await fixture.service.saveNote(note)

    await #expect(throws: VellumError.staleProposal(proposal.id)) {
        try await fixture.service.acceptProposal(id: proposal.id)
    }
    let reloaded = try await fixture.proposals.load(id: proposal.id)
    #expect(reloaded.status.rawValue == ProposalStatus.stale.rawValue)
}

@Test("A custom agent uses the same proposal acceptance seam")
func scriptedAgentAcceptFlow() async throws {
    let root = try makeWorkspaceTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let notes = FileNoteRepository(rootDirectory: root)
    let proposals = FileProposalRepository(rootDirectory: root)
    let activity = FileActivityRepository(rootDirectory: root)
    let spaces = FileSpaceRepository(rootDirectory: root)
    let entities = FileEntityRepository(rootDirectory: root)
    let tasks = FileTaskRepository(rootDirectory: root)
    let service = WorkspaceService(
        notes: notes,
        proposals: proposals,
        activity: activity,
        agent: ScriptedAgent(),
        spaces: spaces,
        entities: entities,
        tasks: tasks
    )
    let note = try await service.createNote(title: "Original")

    let generated = try await service.requestAnalysis(noteID: note.id)
    let accepted = try await service.acceptProposal(id: try #require(generated.first).id)

    #expect(accepted.title == "Scripted title")
    #expect(accepted.revision == 2)
}

@Test("Activity digest filters by date and totals agent action kinds")
func workspaceActivityDigest() async throws {
    let root = try makeWorkspaceTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let activity = FileActivityRepository(rootDirectory: root)
    let service = WorkspaceService(
        notes: FileNoteRepository(rootDirectory: root),
        proposals: FileProposalRepository(rootDirectory: root),
        activity: activity,
        agent: MockVellumAgent(),
        spaces: FileSpaceRepository(rootDirectory: root),
        entities: FileEntityRepository(rootDirectory: root),
        tasks: FileTaskRepository(rootDirectory: root)
    )
    let since = Date(timeIntervalSince1970: 10)
    let events: [(Date, ActivityKind)] = [
        (Date(timeIntervalSince1970: 9), .proposalAccepted),
        (Date(timeIntervalSince1970: 10), .proposalAccepted),
        (Date(timeIntervalSince1970: 11), .taskExtracted),
        (Date(timeIntervalSince1970: 12), .noteUpdated),
        (Date(timeIntervalSince1970: 13), .spaceCreated),
    ]
    for (date, kind) in events {
        try await activity.append(ActivityEvent(id: UUID(), noteID: nil, createdAt: date, kind: kind, message: "Test"))
    }

    let digest = try await service.activityDigest(since: since)

    #expect(digest.countsByKind[.proposalAccepted] == 1)
    #expect(digest.countsByKind[.taskExtracted] == 1)
    #expect(digest.countsByKind[.noteUpdated] == 1)
    #expect(digest.totalAgentActions == 3)
}

@Test("Analysis context includes current space, spaces, and other notes")
func requestAnalysisCarriesKnowledgeContext() async throws {
    let root = try makeWorkspaceTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let notes = FileNoteRepository(rootDirectory: root)
    let spaces = FileSpaceRepository(rootDirectory: root)
    let agent = CapturingAgent()
    let service = WorkspaceService(
        notes: notes,
        proposals: FileProposalRepository(rootDirectory: root),
        activity: FileActivityRepository(rootDirectory: root),
        agent: agent,
        spaces: spaces,
        entities: FileEntityRepository(rootDirectory: root),
        tasks: FileTaskRepository(rootDirectory: root)
    )
    let space = Space(id: UUID(), name: "Research", color: .blue, createdAt: Date())
    try await spaces.save(space)
    var current = try await notes.createNote(title: "Current")
    current.spaceID = space.id
    current.pages[0].plainText = "Context text"
    try await notes.saveNote(current)
    let other = try await notes.createNote(title: "Other")

    _ = try await service.requestAnalysis(noteID: current.id)
    let context = try #require(await agent.context())

    #expect(context.currentSpaceID == space.id)
    #expect(context.spaces.map(\.id) == [space.id])
    #expect(context.spaces.map(\.name) == [space.name])
    #expect(context.spaces.map(\.color) == [space.color])
    #expect(context.otherNotes == [NoteRef(id: other.id, title: other.title)])
    #expect(context.canonicalText == "Context text")
}

@Test("Note summaries expose preview, ink, links, space, and deterministic order")
func workspaceNoteSummaries() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    var older = try await fixture.notes.createNote(title: "Older")
    var newer = try await fixture.notes.createNote(title: "Newer")
    let spaceID = UUID()
    let firstPage = older.pages[0]
    older.pages[0].plainText = "   "
    older.pages.append(
        NotePage(
            id: UUID(),
            order: 1,
            plainText: "  Useful preview text  ",
            drawingAssetPath: "pages/unused/drawing.data",
            background: .blank
        )
    )
    older.spaceID = spaceID
    older.noteType = .pdf
    older.links = [NoteLink(id: UUID(), targetNoteID: newer.id, kind: .related, createdAt: Date())]
    older.updatedAt = Date(timeIntervalSince1970: 1)
    newer.updatedAt = Date(timeIntervalSince1970: 2)
    try await fixture.notes.saveNote(older)
    try await fixture.notes.saveNote(newer)
    try await fixture.notes.saveAsset(Data([1, 2]), noteID: older.id, relativePath: firstPage.drawingAssetPath)

    let summaries = try await fixture.service.listNoteSummaries()

    #expect(summaries.map(\.id) == [newer.id, older.id])
    let summary = try #require(summaries.first { $0.id == older.id })
    #expect(summary.previewText == "Useful preview text")
    #expect(summary.hasInk)
    #expect(summary.linkCount == 1)
    #expect(summary.spaceID == spaceID)
    #expect(summary.noteType == .pdf)
}

private struct ScriptedAgent: VellumAgent, Sendable {
    func analyze(event: WorkspaceEvent, context: AgentContext) async throws -> [AgentProposal] {
        [
            AgentProposal(
                id: UUID(),
                noteID: context.noteID,
                basedOnRevision: context.noteRevision,
                createdAt: event.createdAt,
                title: "Use scripted title",
                explanation: "A test-controlled operation.",
                confidence: 1,
                operation: .suggestTitle("Scripted title"),
                status: .pending
            )
        ]
    }
}

private actor CapturingAgent: VellumAgent {
    private var captured: AgentContext?

    func analyze(event: WorkspaceEvent, context: AgentContext) async throws -> [AgentProposal] {
        captured = context
        return []
    }

    func context() -> AgentContext? {
        captured
    }
}

private struct WorkspaceFixture {
    let root: URL
    let notes: FileNoteRepository
    let proposals: FileProposalRepository
    let spaces: FileSpaceRepository
    let entities: FileEntityRepository
    let tasks: FileTaskRepository
    let service: WorkspaceService

    init() throws {
        let root = try makeWorkspaceTemporaryDirectory()
        self.root = root
        notes = FileNoteRepository(rootDirectory: root)
        proposals = FileProposalRepository(rootDirectory: root)
        spaces = FileSpaceRepository(rootDirectory: root)
        entities = FileEntityRepository(rootDirectory: root)
        tasks = FileTaskRepository(rootDirectory: root)
        service = WorkspaceService(
            notes: notes,
            proposals: proposals,
            activity: FileActivityRepository(rootDirectory: root),
            agent: MockVellumAgent(),
            spaces: spaces,
            entities: entities,
            tasks: tasks
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func makeWorkspaceTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("VellumCoreWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
