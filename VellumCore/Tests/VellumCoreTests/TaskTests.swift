import Foundation
import Testing
@testable import VellumCore

@Test("Task repository upserts without duplicating IDs")
func taskRepositoryUpsert() async throws {
    let fixture = try TaskFixture()
    defer { fixture.cleanup() }
    var task = TaskItem(id: UUID(), noteID: UUID(), pageID: nil, text: "First", isDone: false, createdAt: Date(), completedAt: nil)
    try await fixture.tasks.save(task)
    task.text = "Updated"
    try await fixture.tasks.save(task)
    #expect(try await fixture.tasks.list().map(\.text) == ["Updated"])
}

@Test("Accepting a task proposal leaves sibling proposals fresh")
func taskAcceptancePreservesRevision() async throws {
    let fixture = try TaskFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "Actions")
    let task = taskProposal(note: note, text: "Call client")
    let sibling = AgentProposal(
        id: UUID(), noteID: note.id, basedOnRevision: note.revision, createdAt: Date(),
        title: "Title", explanation: "Test", confidence: 1,
        operation: .suggestTitle("New title"), status: .pending
    )
    try await fixture.proposals.save(task)
    try await fixture.proposals.save(sibling)

    let returned = try await fixture.service.acceptProposal(id: task.id)
    let listed = try await fixture.service.listProposals(noteID: note.id)

    #expect(returned.revision == note.revision)
    #expect(try #require(listed.first { $0.id == sibling.id }).status == .pending)
}

@Test("Equivalent task proposals dedupe after a note revision change")
func taskAcceptanceDedupesAcrossRevisions() async throws {
    let fixture = try TaskFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "Actions")
    let first = taskProposal(note: note, text: " Call Client ")
    try await fixture.proposals.save(first)
    _ = try await fixture.service.acceptProposal(id: first.id)
    var changed = note
    changed.title = "Changed"
    changed = try await fixture.service.saveNote(changed)
    let second = taskProposal(note: changed, text: "call client")
    try await fixture.proposals.save(second)

    _ = try await fixture.service.acceptProposal(id: second.id)

    #expect(try await fixture.tasks.list().count == 1)
}

@Test("Deleting a note removes only its tasks")
func deleteNotePrunesTasks() async throws {
    let fixture = try TaskFixture()
    defer { fixture.cleanup() }
    let removedNote = try await fixture.service.createNote(title: "Remove")
    let keptNote = try await fixture.service.createNote(title: "Keep")
    let removed = TaskItem(id: UUID(), noteID: removedNote.id, pageID: nil, text: "Remove", isDone: false, createdAt: Date(), completedAt: nil)
    let kept = TaskItem(id: UUID(), noteID: keptNote.id, pageID: nil, text: "Keep", isDone: false, createdAt: Date(), completedAt: nil)
    try await fixture.tasks.save(removed)
    try await fixture.tasks.save(kept)

    try await fixture.service.deleteNote(id: removedNote.id)

    #expect(Set(try await fixture.tasks.list().map(\.id)) == Set([removed.id, kept.id]))

    try await fixture.service.purgeNote(id: removedNote.id)

    #expect(try await fixture.tasks.list().map(\.id) == [kept.id])
}

@Test("List tasks places open items first then sorts by creation")
func listTasksOrdering() async throws {
    let fixture = try TaskFixture()
    defer { fixture.cleanup() }
    let noteID = UUID()
    let tasks = [
        TaskItem(id: UUID(), noteID: noteID, pageID: nil, text: "Done early", isDone: true, createdAt: Date(timeIntervalSince1970: 1), completedAt: Date()),
        TaskItem(id: UUID(), noteID: noteID, pageID: nil, text: "Open late", isDone: false, createdAt: Date(timeIntervalSince1970: 3), completedAt: nil),
        TaskItem(id: UUID(), noteID: noteID, pageID: nil, text: "Open early", isDone: false, createdAt: Date(timeIntervalSince1970: 2), completedAt: nil),
    ]
    for task in tasks { try await fixture.tasks.save(task) }
    #expect(try await fixture.service.listTasks().map(\.text) == ["Open early", "Open late", "Done early"])
}

private struct TaskFixture {
    let root: URL
    let proposals: FileProposalRepository
    let tasks: FileTaskRepository
    let service: WorkspaceService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VellumCoreTaskTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        proposals = FileProposalRepository(rootDirectory: root)
        tasks = FileTaskRepository(rootDirectory: root)
        service = WorkspaceService(
            notes: FileNoteRepository(rootDirectory: root),
            proposals: proposals,
            activity: FileActivityRepository(rootDirectory: root),
            agent: HeuristicVellumAgent(),
            spaces: FileSpaceRepository(rootDirectory: root),
            entities: FileEntityRepository(rootDirectory: root),
            tasks: tasks
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func taskProposal(note: Note, text: String) -> AgentProposal {
    AgentProposal(
        id: UUID(),
        noteID: note.id,
        basedOnRevision: note.revision,
        createdAt: Date(),
        title: "Task",
        explanation: "Test",
        confidence: 1,
        operation: .extractTask(text: text, pageID: nil),
        status: .pending
    )
}
