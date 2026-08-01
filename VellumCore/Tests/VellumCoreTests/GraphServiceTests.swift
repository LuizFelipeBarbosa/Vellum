import Foundation
import Testing
@testable import VellumCore

@Test("Graph snapshot has the expected nodes, edges, and connection counts")
func graphSnapshotCountsAndDegrees() async throws {
    let fixture = try GraphFixture()
    defer { fixture.cleanup() }
    let seeded = try await seedGraph(in: fixture)

    let snapshot = try await fixture.service.snapshot()

    #expect(snapshot.nodes.count == 7)
    #expect(snapshot.edges.count == 8)
    #expect(snapshot.edges.filter { edge in
        if case .link = edge.kind { return true }
        return false
    }.count == 3)
    #expect(snapshot.edges.filter { $0.kind == .entityMention }.count == 3)
    #expect(snapshot.edges.filter { $0.kind == .spaceMembership }.count == 2)

    let noteNode = try #require(snapshot.nodes.first { $0.id == .note(seeded.alpha.id) })
    let entityNode = try #require(snapshot.nodes.first { $0.id == .entity(seeded.alice.id) })
    #expect(noteNode.connectionCount == 5)
    #expect(entityNode.connectionCount == 2)
}

@Test("Deleting a linked note filters its node and dangling link edges")
func graphSnapshotFiltersDanglingLinks() async throws {
    let fixture = try GraphFixture()
    defer { fixture.cleanup() }
    let seeded = try await seedGraph(in: fixture)
    try await fixture.notes.deleteNote(id: seeded.gamma.id)

    let snapshot = try await fixture.service.snapshot()

    #expect(!snapshot.nodes.contains { $0.id == .note(seeded.gamma.id) })
    #expect(!snapshot.edges.contains { edge in
        if case .link = edge.kind {
            return edge.target == .note(seeded.gamma.id)
        }
        return false
    })
    #expect(snapshot.edges.count == 6)
    let alphaNode = try #require(snapshot.nodes.first { $0.id == .note(seeded.alpha.id) })
    #expect(alphaNode.connectionCount == 4)
}

@Test("Trashed notes are excluded from the graph and backlinks")
func graphSnapshotFiltersTrashedNotes() async throws {
    let fixture = try GraphFixture()
    defer { fixture.cleanup() }
    let seeded = try await seedGraph(in: fixture)
    try await fixture.workspace.deleteNote(id: seeded.alpha.id)

    let snapshot = try await fixture.service.snapshot()
    let backlinks = try await fixture.service.backlinks(noteID: seeded.gamma.id)

    #expect(!snapshot.nodes.contains { $0.id == .note(seeded.alpha.id) })
    #expect(!snapshot.edges.contains { $0.source == .note(seeded.alpha.id) })
    #expect(!backlinks.contains { $0.sourceNoteID == seeded.alpha.id })
    #expect(backlinks.map(\.sourceNoteID) == [seeded.beta.id])
}

@Test("Multiple sources from one note produce one entity mention edge")
func graphSnapshotDeduplicatesEntityMentions() async throws {
    let fixture = try GraphFixture()
    defer { fixture.cleanup() }
    let seeded = try await seedGraph(in: fixture)

    let snapshot = try await fixture.service.snapshot()
    let matchingEdges = snapshot.edges.filter {
        $0.source == .note(seeded.alpha.id)
            && $0.target == .entity(seeded.alice.id)
            && $0.kind == .entityMention
    }

    // `seedGraph` gives Alice two separate mentions inside note alpha; the snapshot has to
    // collapse them into a single edge.
    #expect(matchingEdges.count == 1)
}

@Test("An empty space is included in the graph")
func graphSnapshotIncludesEmptySpaces() async throws {
    let fixture = try GraphFixture()
    defer { fixture.cleanup() }
    let seeded = try await seedGraph(in: fixture)

    let snapshot = try await fixture.service.snapshot()
    let emptySpaceNode = try #require(
        snapshot.nodes.first { $0.id == .space(seeded.emptySpace.id) }
    )

    #expect(emptySpaceNode.kind == .space)
    #expect(emptySpaceNode.spaceID == seeded.emptySpace.id)
    #expect(emptySpaceNode.connectionCount == 0)
}

@Test("Backlinks include kinds, exclude self-links, and are sorted")
func graphBacklinksAreFilteredAndSorted() async throws {
    let fixture = try GraphFixture()
    defer { fixture.cleanup() }
    let seeded = try await seedGraph(in: fixture)
    var gamma = seeded.gamma
    gamma.links.append(
        NoteLink(
            id: UUID(),
            targetNoteID: gamma.id,
            kind: .mention,
            createdAt: Date(timeIntervalSince1970: 20)
        )
    )
    try await fixture.notes.saveNote(gamma)

    let backlinks = try await fixture.service.backlinks(noteID: gamma.id)

    #expect(backlinks == [
        Backlink(sourceNoteID: seeded.alpha.id, sourceTitle: seeded.alpha.title, kind: .related),
        Backlink(sourceNoteID: seeded.beta.id, sourceTitle: seeded.beta.title, kind: .mention),
    ])
}

@Test("Entities are filtered by note source and sorted by name")
func graphEntitiesAreFilteredAndSorted() async throws {
    let fixture = try GraphFixture()
    defer { fixture.cleanup() }
    let seeded = try await seedGraph(in: fixture)

    let alphaEntities = try await fixture.service.entities(noteID: seeded.alpha.id)
    let gammaEntities = try await fixture.service.entities(noteID: seeded.gamma.id)

    #expect(alphaEntities.map(\.id) == [seeded.alice.id, seeded.swift.id])
    #expect(gammaEntities.isEmpty)
}

@Test("Graph node and edge ordering is deterministic")
func graphSnapshotOrderingIsDeterministic() async throws {
    let fixture = try GraphFixture()
    defer { fixture.cleanup() }
    _ = try await seedGraph(in: fixture)

    let first = try await fixture.service.snapshot()
    let second = try await fixture.service.snapshot()

    #expect(first.nodes == second.nodes)
    #expect(first.edges == second.edges)
}

@Test("Graph node identifiers use stable discriminated coding")
func graphNodeIDStableCoding() throws {
    let id = UUID()
    let variants: [(GraphNodeID, String)] = [
        (.note(id), "note"),
        (.entity(id), "entity"),
        (.space(id), "space"),
    ]

    for (value, type) in variants {
        let data = try JSONEncoder().encode(value)
        let payload = try JSONDecoder().decode([String: String].self, from: data)
        #expect(payload == ["type": type, "id": id.uuidString])
        #expect(try JSONDecoder().decode(GraphNodeID.self, from: data) == value)
    }

    let unknown = Data("{\"type\":\"future\",\"id\":\"\(id.uuidString)\"}".utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(GraphNodeID.self, from: unknown)
    }
}

private struct GraphFixture {
    let root: URL
    let notes: FileNoteRepository
    let spaces: FileSpaceRepository
    let entities: FileEntityRepository
    let service: KnowledgeGraphService
    let workspace: WorkspaceService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VellumCoreGraphTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        notes = FileNoteRepository(rootDirectory: root)
        spaces = FileSpaceRepository(rootDirectory: root)
        entities = FileEntityRepository(rootDirectory: root)
        service = KnowledgeGraphService(notes: notes, spaces: spaces, entities: entities)
        workspace = WorkspaceService(
            notes: notes,
            proposals: FileProposalRepository(rootDirectory: root),
            activity: FileActivityRepository(rootDirectory: root),
            agent: HeuristicVellumAgent(),
            spaces: spaces,
            entities: entities,
            tasks: FileTaskRepository(rootDirectory: root)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct SeededGraph {
    let alpha: Note
    let beta: Note
    let gamma: Note
    let alice: Entity
    let swift: Entity
    let emptySpace: Space
}

private func seedGraph(in fixture: GraphFixture) async throws -> SeededGraph {
    let createdAt = Date(timeIntervalSince1970: 10)
    let workSpace = Space(id: UUID(), name: "Work", color: .blue, createdAt: createdAt)
    let emptySpace = Space(id: UUID(), name: "Empty", color: .gray, createdAt: createdAt.addingTimeInterval(1))
    try await fixture.spaces.save(workSpace)
    try await fixture.spaces.save(emptySpace)

    let betaID = UUID()
    let gammaID = UUID()
    let alpha = Note(
        id: UUID(),
        schemaVersion: Note.currentSchemaVersion,
        revision: 1,
        title: "Alpha",
        tags: [],
        createdAt: createdAt,
        updatedAt: createdAt,
        pages: [],
        noteType: .note,
        spaceID: workSpace.id,
        links: [
            NoteLink(id: UUID(), targetNoteID: betaID, kind: .mention, createdAt: createdAt),
            NoteLink(id: UUID(), targetNoteID: gammaID, kind: .related, createdAt: createdAt),
        ]
    )
    let beta = Note(
        id: betaID,
        schemaVersion: Note.currentSchemaVersion,
        revision: 1,
        title: "Beta",
        tags: [],
        createdAt: createdAt,
        updatedAt: createdAt.addingTimeInterval(1),
        pages: [],
        noteType: .pdf,
        spaceID: workSpace.id,
        links: [
            NoteLink(id: UUID(), targetNoteID: gammaID, kind: .mention, createdAt: createdAt),
        ]
    )
    let gamma = Note(
        id: gammaID,
        schemaVersion: Note.currentSchemaVersion,
        revision: 1,
        title: "Gamma",
        tags: [],
        createdAt: createdAt,
        updatedAt: createdAt.addingTimeInterval(2),
        pages: [],
        noteType: .deck,
        spaceID: nil,
        links: []
    )
    try await fixture.notes.insertNote(alpha)
    try await fixture.notes.insertNote(beta)
    try await fixture.notes.insertNote(gamma)

    let alice = Entity(
        id: UUID(),
        name: "Alice",
        kind: .person,
        sources: [
            EntitySource(noteID: alpha.id, pageID: nil, excerpt: "First mention"),
            EntitySource(noteID: alpha.id, pageID: UUID(), excerpt: "Second mention"),
            EntitySource(noteID: beta.id, pageID: nil, excerpt: nil),
        ],
        createdAt: createdAt
    )
    let swift = Entity(
        id: UUID(),
        name: "Swift",
        kind: .topic,
        sources: [
            EntitySource(noteID: alpha.id, pageID: nil, excerpt: "Language"),
            EntitySource(noteID: UUID(), pageID: nil, excerpt: "Missing note"),
        ],
        createdAt: createdAt.addingTimeInterval(1)
    )
    try await fixture.entities.save(alice)
    try await fixture.entities.save(swift)

    return SeededGraph(
        alpha: alpha,
        beta: beta,
        gamma: gamma,
        alice: alice,
        swift: swift,
        emptySpace: emptySpace
    )
}
