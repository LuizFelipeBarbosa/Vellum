import Foundation
import Testing
@testable import VellumCore

@Test("Adding a link persists it and bumps revision")
func addNoteLink() async throws {
    let fixture = try LinkFixture()
    defer { fixture.cleanup() }
    let source = try await fixture.service.createNote(title: "Source")
    let target = try await fixture.service.createNote(title: "Target")

    let linked = try await fixture.service.addLink(fromNoteID: source.id, to: target.id, kind: .mention)

    #expect(linked.revision == source.revision + 1)
    #expect(linked.links.count == 1)
    #expect(linked.links[0].targetNoteID == target.id)
    #expect(try await fixture.service.activity(noteID: source.id).contains { $0.kind == .notesLinked })
}

@Test("Adding the same target and kind is a revision-preserving no-op")
func duplicateNoteLinkIsNoOp() async throws {
    let fixture = try LinkFixture()
    defer { fixture.cleanup() }
    let source = try await fixture.service.createNote(title: "Source")
    let target = try await fixture.service.createNote(title: "Target")
    let first = try await fixture.service.addLink(fromNoteID: source.id, to: target.id, kind: .related)

    let second = try await fixture.service.addLink(fromNoteID: source.id, to: target.id, kind: .related)

    #expect(second.revision == first.revision)
    #expect(second.links.map(\.id) == first.links.map(\.id))
    #expect(second.links.map(\.targetNoteID) == first.links.map(\.targetNoteID))
    #expect(second.links.map(\.kind) == first.links.map(\.kind))
}

@Test("A different link kind to the same target is retained")
func distinctLinkKindsAreAllowed() async throws {
    let fixture = try LinkFixture()
    defer { fixture.cleanup() }
    let source = try await fixture.service.createNote(title: "Source")
    let target = try await fixture.service.createNote(title: "Target")
    _ = try await fixture.service.addLink(fromNoteID: source.id, to: target.id, kind: .mention)
    let linked = try await fixture.service.addLink(fromNoteID: source.id, to: target.id, kind: .related)
    #expect(Set(linked.links.map(\.kind)) == Set([.mention, .related]))
}

@Test("A dangling target is rejected without changing the source")
func danglingTargetIsRejected() async throws {
    let fixture = try LinkFixture()
    defer { fixture.cleanup() }
    let source = try await fixture.service.createNote(title: "Source")
    let missing = UUID()

    await #expect(throws: VellumError.noteNotFound(missing)) {
        try await fixture.service.addLink(fromNoteID: source.id, to: missing, kind: .mention)
    }
    #expect(try await fixture.service.loadNote(id: source.id).links.isEmpty)
}

@Test("A link proposal adds a link and is accepted")
func acceptLinkProposal() async throws {
    let fixture = try LinkFixture()
    defer { fixture.cleanup() }
    let source = try await fixture.service.createNote(title: "Source")
    let target = try await fixture.service.createNote(title: "Target")
    let proposal = linkProposal(note: source, target: target.id)
    try await fixture.proposals.save(proposal)

    let accepted = try await fixture.service.acceptProposal(id: proposal.id)

    #expect(accepted.links.first?.targetNoteID == target.id)
    #expect(try await fixture.proposals.load(id: proposal.id).status == .accepted)
}

@Test("Removing a link persists the removal")
func removeNoteLink() async throws {
    let fixture = try LinkFixture()
    defer { fixture.cleanup() }
    let source = try await fixture.service.createNote(title: "Source")
    let target = try await fixture.service.createNote(title: "Target")
    let linked = try await fixture.service.addLink(fromNoteID: source.id, to: target.id, kind: .mention)
    let linkID = try #require(linked.links.first?.id)

    let removed = try await fixture.service.removeLink(fromNoteID: source.id, linkID: linkID)

    #expect(removed.links.isEmpty)
    #expect(removed.revision == linked.revision + 1)
}

private struct LinkFixture {
    let root: URL
    let proposals: FileProposalRepository
    let service: WorkspaceService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VellumCoreLinkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        proposals = FileProposalRepository(rootDirectory: root)
        service = WorkspaceService(
            notes: FileNoteRepository(rootDirectory: root),
            proposals: proposals,
            activity: FileActivityRepository(rootDirectory: root),
            agent: MockVellumAgent(),
            spaces: FileSpaceRepository(rootDirectory: root),
            entities: FileEntityRepository(rootDirectory: root),
            tasks: FileTaskRepository(rootDirectory: root)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func linkProposal(note: Note, target: UUID) -> AgentProposal {
    AgentProposal(
        id: UUID(),
        noteID: note.id,
        basedOnRevision: note.revision,
        createdAt: Date(),
        title: "Link",
        explanation: "Test",
        confidence: 1,
        operation: .linkNotes(targetNoteID: target, kind: .mention),
        status: .pending
    )
}
