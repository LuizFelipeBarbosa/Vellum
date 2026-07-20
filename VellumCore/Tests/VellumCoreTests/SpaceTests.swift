import Foundation
import Testing
@testable import VellumCore

@Test("A fresh space repository is empty")
func freshSpaceRepository() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    #expect(try await fixture.spaces.list().isEmpty)
}

@Test("Space repository upserts and sorts deterministically")
func spaceRepositoryUpsertAndSort() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let later = Space(id: UUID(), name: "Later", color: .blue, createdAt: Date(timeIntervalSince1970: 2))
    var earlier = Space(id: UUID(), name: "Earlier", color: .red, createdAt: Date(timeIntervalSince1970: 1))
    try await fixture.spaces.save(later)
    try await fixture.spaces.save(earlier)
    earlier.name = "Renamed"
    try await fixture.spaces.save(earlier)

    let listed = try await fixture.spaces.list()
    #expect(listed.map(\.id) == [earlier.id, later.id])
    #expect(listed[0].name == "Renamed")
}

@Test("Space repository deletion is idempotent")
func spaceRepositoryDeleteIsIdempotent() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let space = Space(id: UUID(), name: "Delete", color: .gray, createdAt: Date())
    try await fixture.spaces.save(space)
    try await fixture.spaces.delete(id: space.id)
    try await fixture.spaces.delete(id: space.id)
    #expect(try await fixture.spaces.list().isEmpty)
}

@Test("Create space logs activity and listSpaces counts assigned notes")
func createAndListSpaces() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let space = try await fixture.service.createSpace(name: "Work", color: .teal)
    let first = try await fixture.service.createNote(title: "First")
    _ = try await fixture.service.createNote(title: "Second")
    _ = try await fixture.service.assignNote(id: first.id, toSpaceID: space.id)

    let listing = try #require(try await fixture.service.listSpaces().first)
    #expect(listing.space.id == space.id)
    #expect(listing.space.name == space.name)
    #expect(listing.space.color == space.color)
    #expect(listing.noteCount == 1)
    #expect(try await fixture.service.activity(noteID: nil).contains { $0.kind == .spaceCreated })
}

@Test("Space repository decodes legacy spaces without parent IDs")
func legacySpaceWithoutParentIDDecodes() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let id = UUID()
    let json = """
        [
          {
            "color": "blue",
            "createdAt": "2024-01-01T00:00:00.000Z",
            "id": "\(id.uuidString)",
            "name": "Legacy"
          }
        ]
        """
    try Data(json.utf8).write(to: fixture.root.appendingPathComponent("spaces.json"))

    let listed = try await fixture.spaces.list()

    #expect(listed.count == 1)
    #expect(listed[0].id == id)
    #expect(listed[0].parentID == nil)
}

@Test("Creating a subspace stores its parent ID")
func createSubspaceStoresParentID() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let root = try await fixture.service.createSpace(name: "Root", color: .blue)

    let child = try await fixture.service.createSpace(
        name: "Child",
        color: .teal,
        parentID: root.id
    )

    #expect(child.parentID == root.id)
    #expect(try await fixture.spaces.list().first { $0.id == child.id }?.parentID == root.id)
}

@Test("Subspaces cannot contain subspaces")
func subspaceNestingIsRejected() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let root = try await fixture.service.createSpace(name: "Root", color: .blue)
    let child = try await fixture.service.createSpace(
        name: "Child",
        color: .teal,
        parentID: root.id
    )

    await #expect(throws: VellumError.invalidSubspaceNesting) {
        try await fixture.service.createSpace(
            name: "Grandchild",
            color: .green,
            parentID: child.id
        )
    }
}

@Test("Creating a subspace requires an existing parent")
func missingSubspaceParentIsRejected() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let missingID = UUID()

    await #expect(throws: VellumError.spaceNotFound(missingID)) {
        try await fixture.service.createSpace(
            name: "Orphan",
            color: .gray,
            parentID: missingID
        )
    }
}

@Test("Deleting a space removes subspaces and trashes contained notes")
func deleteSpaceCascadesToSubspacesAndNotes() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let parent = try await fixture.service.createSpace(name: "Parent", color: .purple)
    let child = try await fixture.service.createSpace(
        name: "Child",
        color: .orange,
        parentID: parent.id
    )
    let parentNote = try await fixture.service.createNote(title: "Parent note")
    let childNote = try await fixture.service.createNote(title: "Child note")
    let alreadyTrashedNote = try await fixture.service.createNote(title: "Already trashed note")
    _ = try await fixture.service.assignNote(id: parentNote.id, toSpaceID: parent.id)
    _ = try await fixture.service.assignNote(id: childNote.id, toSpaceID: child.id)
    _ = try await fixture.service.assignNote(id: alreadyTrashedNote.id, toSpaceID: parent.id)
    try await fixture.service.deleteNote(id: alreadyTrashedNote.id)

    try await fixture.service.deleteSpace(id: parent.id)

    #expect(try await fixture.spaces.list().isEmpty)
    let trashedIDs = Set(try await fixture.service.listTrashedNotes().map(\.id))
    #expect(trashedIDs == Set([parentNote.id, childNote.id, alreadyTrashedNote.id]))
    #expect(try await fixture.service.loadNote(id: parentNote.id).spaceID == nil)
    #expect(try await fixture.service.loadNote(id: alreadyTrashedNote.id).spaceID == nil)

    let restored = try await fixture.service.restoreNote(id: parentNote.id)
    #expect(restored.spaceID == nil)
    let activeIDs = Set(try await fixture.service.listNotes().map(\.id))
    #expect(activeIDs.contains(parentNote.id))
    #expect(!activeIDs.contains(childNote.id))
    #expect(!activeIDs.contains(alreadyTrashedNote.id))
    #expect(try await fixture.service.activity(noteID: nil).contains { $0.kind == .spaceDeleted })
}

@Test("Deleting an unknown space reports space not found")
func deleteUnknownSpaceIsRejected() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let missingID = UUID()

    await #expect(throws: VellumError.spaceNotFound(missingID)) {
        try await fixture.service.deleteSpace(id: missingID)
    }
}

@Test("Assign note bumps revision and records filing activity")
func assignNoteToSpace() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "File me")
    let space = try await fixture.service.createSpace(name: "Home", color: .green)

    let assigned = try await fixture.service.assignNote(id: note.id, toSpaceID: space.id)

    #expect(assigned.spaceID == space.id)
    #expect(assigned.revision == note.revision + 1)
    let events = try await fixture.service.activity(noteID: note.id)
    #expect(events.contains { $0.kind == .noteUpdated })
    #expect(events.contains { $0.kind == .noteFiledToSpace })
}

@Test("File-to-space proposal matches an existing name case-insensitively")
func proposalFilesToExistingSpace() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let space = try await fixture.service.createSpace(name: "Research", color: .purple)
    let note = try await fixture.service.createNote(title: "Paper")
    let proposal = spaceProposal(note: note, operation: .fileToSpace(spaceName: "research", color: .red))
    try await fixture.proposals.save(proposal)

    let accepted = try await fixture.service.acceptProposal(id: proposal.id)

    #expect(accepted.spaceID == space.id)
    #expect(try await fixture.spaces.list().count == 1)
}

@Test("File-to-space proposal creates a missing space once")
func proposalCreatesMissingSpace() async throws {
    let fixture = try SpaceFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "Trips")
    let proposal = spaceProposal(note: note, operation: .fileToSpace(spaceName: "Travel", color: .orange))
    try await fixture.proposals.save(proposal)

    let accepted = try await fixture.service.acceptProposal(id: proposal.id)

    let spaces = try await fixture.spaces.list()
    #expect(spaces.count == 1)
    #expect(accepted.spaceID == spaces[0].id)
    let created = try await fixture.service.activity(noteID: nil).filter { $0.kind == .spaceCreated }
    #expect(created.count == 1)
}

@Test("Unknown activity kinds decode tolerantly and encode as unknown")
func unknownActivityKindIsTolerated() throws {
    let decoded = try JSONDecoder().decode(ActivityKind.self, from: Data("\"futureKind\"".utf8))
    #expect(decoded == .unknown)
    #expect(String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self) == "\"unknown\"")

    let spaceDeleted = try JSONDecoder().decode(
        ActivityKind.self,
        from: JSONEncoder().encode(ActivityKind.spaceDeleted)
    )
    #expect(spaceDeleted == .spaceDeleted)
}

private struct SpaceFixture {
    let root: URL
    let notes: FileNoteRepository
    let proposals: FileProposalRepository
    let spaces: FileSpaceRepository
    let service: WorkspaceService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VellumCoreSpaceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        notes = FileNoteRepository(rootDirectory: root)
        proposals = FileProposalRepository(rootDirectory: root)
        spaces = FileSpaceRepository(rootDirectory: root)
        service = WorkspaceService(
            notes: notes,
            proposals: proposals,
            activity: FileActivityRepository(rootDirectory: root),
            agent: MockVellumAgent(),
            spaces: spaces,
            entities: FileEntityRepository(rootDirectory: root),
            tasks: FileTaskRepository(rootDirectory: root)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func spaceProposal(note: Note, operation: AgentOperation) -> AgentProposal {
    AgentProposal(
        id: UUID(),
        noteID: note.id,
        basedOnRevision: note.revision,
        createdAt: Date(),
        title: "Space operation",
        explanation: "Test",
        confidence: 1,
        operation: operation,
        status: .pending
    )
}
