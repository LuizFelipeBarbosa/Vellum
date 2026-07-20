import Foundation
import Testing
@testable import VellumCore

@Test("A fresh entity repository is empty")
func freshEntityRepository() async throws {
    let fixture = try EntityFixture()
    defer { fixture.cleanup() }
    #expect(try await fixture.entities.list().isEmpty)
}

@Test("Entity repository upserts and orders by creation date")
func entityRepositoryUpsertAndSort() async throws {
    let fixture = try EntityFixture()
    defer { fixture.cleanup() }
    let source = EntitySource(noteID: UUID(), pageID: nil, excerpt: nil)
    let later = Entity(id: UUID(), name: "Later", kind: .topic, sources: [source], createdAt: Date(timeIntervalSince1970: 2))
    var earlier = Entity(id: UUID(), name: "Earlier", kind: .person, sources: [source], createdAt: Date(timeIntervalSince1970: 1))
    try await fixture.entities.save(later)
    try await fixture.entities.save(earlier)
    earlier.name = "Renamed"
    try await fixture.entities.save(earlier)
    #expect(try await fixture.entities.list().map(\.name) == ["Renamed", "Later"])
}

@Test("Accepting an entity proposal creates an entity without changing note revision")
func acceptEntityCreates() async throws {
    let fixture = try EntityFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "People")
    let proposal = entityProposal(note: note, name: "Marco Alves", excerpt: "Met Marco Alves.")
    try await fixture.proposals.save(proposal)

    let returned = try await fixture.service.acceptProposal(id: proposal.id)

    let entity = try #require(try await fixture.entities.list().first)
    #expect(returned.revision == note.revision)
    #expect(entity.name == "Marco Alves")
    #expect(entity.sources == [EntitySource(noteID: note.id, pageID: nil, excerpt: "Met Marco Alves.")])
}

@Test("Entity acceptance merges distinct sources and suppresses equal sources")
func acceptEntityMergesSources() async throws {
    let fixture = try EntityFixture()
    defer { fixture.cleanup() }
    let firstNote = try await fixture.service.createNote(title: "One")
    let secondNote = try await fixture.service.createNote(title: "Two")
    let first = entityProposal(note: firstNote, name: "Marco Alves", excerpt: "First")
    let duplicate = entityProposal(note: firstNote, name: "marco alves", excerpt: "First")
    let second = entityProposal(note: secondNote, name: "MARCO ALVES", excerpt: "Second")
    for proposal in [first, duplicate, second] {
        try await fixture.proposals.save(proposal)
        _ = try await fixture.service.acceptProposal(id: proposal.id)
    }

    let entities = try await fixture.entities.list()
    #expect(entities.count == 1)
    #expect(entities[0].sources.count == 2)
    #expect(Set(entities[0].sources.map(\.noteID)) == Set([firstNote.id, secondNote.id]))
}

@Test("Deleting notes prunes entity sources and removes empty entities")
func deleteNotePrunesEntities() async throws {
    let fixture = try EntityFixture()
    defer { fixture.cleanup() }
    let first = try await fixture.service.createNote(title: "One")
    let second = try await fixture.service.createNote(title: "Two")
    let entity = Entity(
        id: UUID(),
        name: "Shared Topic",
        kind: .topic,
        sources: [
            EntitySource(noteID: first.id, pageID: nil, excerpt: nil),
            EntitySource(noteID: second.id, pageID: nil, excerpt: nil),
        ],
        createdAt: Date()
    )
    try await fixture.entities.save(entity)

    try await fixture.service.deleteNote(id: first.id)
    #expect(
        try await fixture.entities.list().first?.sources.map(\.noteID)
            == [first.id, second.id]
    )
    try await fixture.service.purgeNote(id: first.id)
    #expect(try await fixture.entities.list().first?.sources.map(\.noteID) == [second.id])
    try await fixture.service.purgeNote(id: second.id)
    #expect(try await fixture.entities.list().isEmpty)
}

@Test("Entity extraction records dedicated and accepted activity")
func entityExtractionActivity() async throws {
    let fixture = try EntityFixture()
    defer { fixture.cleanup() }
    let note = try await fixture.service.createNote(title: "People")
    let proposal = entityProposal(note: note, name: "Marco Alves", excerpt: nil)
    try await fixture.proposals.save(proposal)
    _ = try await fixture.service.acceptProposal(id: proposal.id)
    let events = try await fixture.service.activity(noteID: note.id)
    #expect(events.contains { $0.kind == .entityExtracted })
    #expect(events.contains { $0.kind == .proposalAccepted })
}

private struct EntityFixture {
    let root: URL
    let proposals: FileProposalRepository
    let entities: FileEntityRepository
    let service: WorkspaceService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VellumCoreEntityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        proposals = FileProposalRepository(rootDirectory: root)
        entities = FileEntityRepository(rootDirectory: root)
        service = WorkspaceService(
            notes: FileNoteRepository(rootDirectory: root),
            proposals: proposals,
            activity: FileActivityRepository(rootDirectory: root),
            agent: MockVellumAgent(),
            spaces: FileSpaceRepository(rootDirectory: root),
            entities: entities,
            tasks: FileTaskRepository(rootDirectory: root)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func entityProposal(note: Note, name: String, excerpt: String?) -> AgentProposal {
    AgentProposal(
        id: UUID(),
        noteID: note.id,
        basedOnRevision: note.revision,
        createdAt: Date(),
        title: "Entity",
        explanation: "Test",
        confidence: 1,
        operation: .extractEntity(name: name, kind: .person, pageID: nil, excerpt: excerpt),
        status: .pending
    )
}
