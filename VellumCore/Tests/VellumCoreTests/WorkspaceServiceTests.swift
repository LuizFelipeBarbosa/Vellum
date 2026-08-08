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
    #expect(accepted.titleOrigin == .manual)
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
    let root = try TemporaryDirectory.make()
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
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let activity = FileActivityRepository(rootDirectory: root)
    let service = WorkspaceService(
        notes: FileNoteRepository(rootDirectory: root),
        proposals: FileProposalRepository(rootDirectory: root),
        activity: activity,
        agent: HeuristicVellumAgent(),
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

@Test("Analysis context includes existing workspace knowledge")
func requestAnalysisCarriesKnowledgeContext() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let notes = FileNoteRepository(rootDirectory: root)
    let spaces = FileSpaceRepository(rootDirectory: root)
    let entities = FileEntityRepository(rootDirectory: root)
    let agent = CapturingAgent()
    let service = WorkspaceService(
        notes: notes,
        proposals: FileProposalRepository(rootDirectory: root),
        activity: FileActivityRepository(rootDirectory: root),
        agent: agent,
        spaces: spaces,
        entities: entities,
        tasks: FileTaskRepository(rootDirectory: root)
    )
    let space = Space(id: UUID(), name: "Research", color: .blue, createdAt: Date())
    try await spaces.save(space)
    var current = try await notes.createNote(title: "Current")
    current.spaceID = space.id
    current.tags = ["swift", "research"]
    current.pages[0].plainText = "Context text"
    var other = try await notes.createNote(title: "Other")
    other.pages[0].plainText = "   "
    let otherPreview = "Useful preview " + String(repeating: "detail ", count: 30)
    other.pages.append(
        NotePage(
            id: UUID(),
            order: 2,
            plainText: "Later page",
            drawingAssetPath: "pages/later/drawing.data",
            background: .blank
        )
    )
    other.pages.append(
        NotePage(
            id: UUID(),
            order: 1,
            plainText: "  \(otherPreview)  ",
            drawingAssetPath: "pages/preview/drawing.data",
            background: .blank
        )
    )
    try await notes.saveNote(other)
    var secondOther = try await notes.createNote(title: "Second Other")
    secondOther.pages[0].plainText = "Second preview"
    try await notes.saveNote(secondOther)
    current.links = [
        NoteLink(id: UUID(), targetNoteID: other.id, kind: .related, createdAt: Date()),
        NoteLink(id: UUID(), targetNoteID: other.id, kind: .mention, createdAt: Date()),
        NoteLink(id: UUID(), targetNoteID: secondOther.id, kind: .related, createdAt: Date()),
    ]
    try await notes.saveNote(current)
    let currentSource = EntitySource(noteID: current.id, pageID: nil, excerpt: nil)
    try await entities.save(
        Entity(
            id: UUID(),
            name: "Vellum",
            kind: .topic,
            sources: [currentSource],
            createdAt: Date(timeIntervalSince1970: 1)
        )
    )
    try await entities.save(
        Entity(
            id: UUID(),
            name: "Vellum",
            kind: .document,
            sources: [currentSource],
            createdAt: Date(timeIntervalSince1970: 2)
        )
    )
    try await entities.save(
        Entity(
            id: UUID(),
            name: "Other Entity",
            kind: .topic,
            sources: [EntitySource(noteID: other.id, pageID: nil, excerpt: nil)],
            createdAt: Date(timeIntervalSince1970: 3)
        )
    )

    _ = try await service.requestAnalysis(noteID: current.id)
    let context = try #require(await agent.context())

    #expect(context.currentSpaceID == space.id)
    #expect(context.spaces.map(\.id) == [space.id])
    #expect(context.spaces.map(\.name) == [space.name])
    #expect(context.spaces.map(\.color) == [space.color])
    #expect(context.otherNotes.count == 2)
    #expect(context.otherNotes.first { $0.id == other.id }?.preview == String(otherPreview.prefix(160)))
    #expect(context.otherNotes.first { $0.id == secondOther.id }?.preview == "Second preview")
    #expect(context.canonicalText == "Context text")
    #expect(context.existingTags == ["swift", "research"])
    #expect(context.existingLinkTargetIDs == [other.id, secondOther.id])
    #expect(context.existingEntityNames == ["Vellum"])
}

@Test("Soft-deleted notes are hidden from workspace knowledge listings")
func softDeleteHidesNoteFromWorkspaceKnowledge() async throws {
    let agent = CapturingAgent()
    let fixture = try WorkspaceFixture(agent: agent)
    defer { fixture.cleanup() }
    let space = try await fixture.service.createSpace(name: "Research", color: .blue)
    var current = try await fixture.service.createNote(title: "Current")
    current.pages[0].plainText = "Current context"
    try await fixture.notes.saveNote(current)
    let trashed = try await fixture.service.createNote(title: "Trashed")
    try await fixture.service.assignNotes(ids: [current.id, trashed.id], toSpaceID: space.id)

    try await fixture.service.deleteNote(id: trashed.id)

    #expect(try await fixture.service.loadNote(id: trashed.id).deletedAt != nil)
    #expect(try await fixture.service.listNotes().map(\.id) == [current.id])
    #expect(try await fixture.service.listNoteSummaries().map(\.id) == [current.id])
    #expect(try await fixture.service.listSpaces().first?.noteCount == 1)

    _ = try await fixture.service.requestAnalysis(noteID: current.id)
    let context = try #require(await agent.context())
    #expect(context.otherNotes.isEmpty)
}

@Test("Restoring a note returns it to active listings")
func restoreNoteRoundTrip() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "Restore")
    try await fixture.service.deleteNote(id: note.id)

    let restored = try await fixture.service.restoreNote(id: note.id)

    #expect(restored.deletedAt == nil)
    #expect(try await fixture.service.loadNote(id: note.id).deletedAt == nil)
    #expect(try await fixture.service.listNotes().map(\.id) == [note.id])
}

@Test("Saving a stale note preserves its on-disk deletion state")
func saveNotePreservesDeletedAt() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    let stale = try await fixture.service.createNote(title: "Stale")
    try await fixture.service.deleteNote(id: stale.id)

    _ = try await fixture.service.saveNote(stale)

    #expect(try await fixture.service.loadNote(id: stale.id).deletedAt != nil)
    #expect(try await fixture.service.listNotes().isEmpty)
}

@Test("Purging an active note is a no-op")
func purgeActiveNoteDoesNothing() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "Keep")

    try await fixture.service.purgeNote(id: note.id)

    #expect(try await fixture.service.loadNote(id: note.id).id == note.id)
    #expect(try await fixture.service.listNotes().map(\.id) == [note.id])
}

@Test("Purging a note removes its package, tasks, and entity sources")
func purgeNoteCascades() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "Purge")
    let task = TaskItem(
        id: UUID(),
        noteID: note.id,
        pageID: nil,
        text: "Remove",
        isDone: false,
        createdAt: Date(),
        completedAt: nil
    )
    let entity = Entity(
        id: UUID(),
        name: "Remove",
        kind: .topic,
        sources: [EntitySource(noteID: note.id, pageID: nil, excerpt: nil)],
        createdAt: Date()
    )
    try await fixture.tasks.save(task)
    try await fixture.entities.save(entity)
    try await fixture.service.deleteNote(id: note.id)

    try await fixture.service.purgeNote(id: note.id)

    #expect(try await fixture.tasks.list().isEmpty)
    #expect(try await fixture.entities.list().isEmpty)
    await #expect(throws: VellumError.noteNotFound(note.id)) {
        try await fixture.service.loadNote(id: note.id)
    }
}

@Test("A stale purge after restore is a no-op")
func purgeAfterRestoreDoesNothing() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "Restored")
    try await fixture.service.deleteNote(id: note.id)
    _ = try await fixture.service.restoreNote(id: note.id)

    try await fixture.service.purgeNote(id: note.id)

    #expect(try await fixture.service.loadNote(id: note.id).deletedAt == nil)
    #expect(try await fixture.service.listNotes().map(\.id) == [note.id])
}

@Test("Emptying Trash permanently removes every trashed note")
func emptyTrashPurgesTrashedNotes() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    let first = try await fixture.service.createNote(title: "First")
    let second = try await fixture.service.createNote(title: "Second")
    try await fixture.service.deleteNotes(ids: [first.id, second.id])

    try await fixture.service.emptyTrash()

    #expect(try await fixture.service.listTrashedNotes().isEmpty)
    await #expect(throws: VellumError.noteNotFound(first.id)) {
        try await fixture.service.loadNote(id: first.id)
    }
    await #expect(throws: VellumError.noteNotFound(second.id)) {
        try await fixture.service.loadNote(id: second.id)
    }
}

@Test("Bulk note operations assign, trash, and restore notes")
func bulkNoteOperations() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    let space = try await fixture.service.createSpace(name: "Bulk", color: .green)
    let first = try await fixture.service.createNote(title: "First")
    let second = try await fixture.service.createNote(title: "Second")
    try await fixture.service.assignNotes(ids: [first.id, second.id], toSpaceID: space.id)

    #expect(try await fixture.service.loadNote(id: first.id).spaceID == space.id)
    #expect(try await fixture.service.loadNote(id: second.id).spaceID == space.id)

    try await fixture.service.deleteNotes(ids: [first.id, second.id])
    #expect(Set(try await fixture.service.listTrashedNotes().map(\.id)) == Set([first.id, second.id]))

    try await fixture.service.purgeNote(id: first.id)
    try await fixture.service.restoreNotes(ids: [first.id, UUID(), second.id])

    #expect(try await fixture.service.loadNote(id: second.id).deletedAt == nil)
    #expect(try await fixture.service.listNotes().map(\.id) == [second.id])
}

@Test("Bulk trash skips already trashed and missing notes")
func bulkTrashSkipsAlreadyTrashedAndMissingNotes() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    let first = try await fixture.service.createNote(title: "First")
    let second = try await fixture.service.createNote(title: "Second")
    let third = try await fixture.service.createNote(title: "Third")
    try await fixture.service.deleteNote(id: first.id)
    try await fixture.service.deleteNote(id: second.id)
    try await fixture.service.purgeNote(id: second.id)

    let trashedIDs = try await fixture.service.deleteNotes(ids: [first.id, second.id, third.id])

    #expect(trashedIDs == [third.id])
    #expect(try await fixture.service.loadNote(id: third.id).isTrashed)
}

@Test("Trash lifecycle records dedicated activity kinds")
func trashLifecycleActivity() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "Activity")

    try await fixture.service.deleteNote(id: note.id)
    var activity = try await fixture.service.activity(noteID: note.id)
    #expect(activity.contains { $0.kind.rawValue == ActivityKind.noteTrashed.rawValue })

    _ = try await fixture.service.restoreNote(id: note.id)
    activity = try await fixture.service.activity(noteID: note.id)
    #expect(activity.contains { $0.kind.rawValue == ActivityKind.noteRestored.rawValue })

    try await fixture.service.deleteNote(id: note.id)
    try await fixture.service.purgeNote(id: note.id)
    activity = try await fixture.service.activity(noteID: nil)
    #expect(activity.contains { $0.kind.rawValue == ActivityKind.notePurged.rawValue })
    // The purge event is written after the package is gone, so it lands in the
    // workspace log — the note-scoped list has to reach it there too.
    activity = try await fixture.service.activity(noteID: note.id)
    #expect(activity.map(\.kind.rawValue) == [ActivityKind.notePurged.rawValue])
}

@Test("Note-scoped listing reaches events appended without a package")
func activityListedForNoteWithoutPackage() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let activity = FileActivityRepository(rootDirectory: root)
    let noteID = UUID()
    let otherNoteID = UUID()
    let events: [(UUID?, ActivityKind)] = [
        (noteID, .notePurged),
        (otherNoteID, .notePurged),
        (nil, .workspaceSeeded),
    ]
    for (index, event) in events.enumerated() {
        try await activity.append(
            ActivityEvent(
                id: UUID(),
                noteID: event.0,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                kind: event.1,
                message: "Test"
            )
        )
    }

    let listed = try await activity.list(noteID: noteID)

    #expect(listed.map(\.noteID) == [noteID])
    #expect(try await activity.list(noteID: nil).count == 3)
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
    older.tags = ["work", "urgent"]
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
    #expect(summary.tags == ["work", "urgent"])
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

    init(agent: any VellumAgent = HeuristicVellumAgent()) throws {
        let root = try TemporaryDirectory.make()
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
            agent: agent,
            spaces: spaces,
            entities: entities,
            tasks: tasks
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
