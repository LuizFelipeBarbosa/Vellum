import Foundation

public actor KnowledgeGraphService {
    private let notes: any NoteRepository
    private let spaces: any SpaceRepository
    private let entities: any EntityRepository

    public init(
        notes: any NoteRepository,
        spaces: any SpaceRepository,
        entities: any EntityRepository
    ) {
        self.notes = notes
        self.spaces = spaces
        self.entities = entities
    }

    public func snapshot() async throws -> GraphSnapshot {
        async let listedNotes = notes.listNotes()
        async let listedSpaces = spaces.list()
        async let listedEntities = entities.list()
        let (notes, spaces, entities) = try await (listedNotes, listedSpaces, listedEntities)

        let noteIDs = Set(notes.map(\.id))
        let spaceIDs = Set(spaces.map(\.id))
        let includedEntities = entities.filter { entity in
            entity.sources.contains { noteIDs.contains($0.noteID) }
        }

        var edges: [GraphEdge] = []
        for note in notes {
            for link in note.links where noteIDs.contains(link.targetNoteID) {
                edges.append(
                    GraphEdge(
                        source: .note(note.id),
                        target: .note(link.targetNoteID),
                        kind: .link(link.kind)
                    )
                )
            }
        }

        for entity in includedEntities {
            let sourceNoteIDs = Set(
                entity.sources.lazy
                    .map(\.noteID)
                    .filter { noteIDs.contains($0) }
            )
            for noteID in sourceNoteIDs {
                edges.append(
                    GraphEdge(
                        source: .note(noteID),
                        target: .entity(entity.id),
                        kind: .entityMention
                    )
                )
            }
        }

        for note in notes {
            if let spaceID = note.spaceID, spaceIDs.contains(spaceID) {
                edges.append(
                    GraphEdge(
                        source: .note(note.id),
                        target: .space(spaceID),
                        kind: .spaceMembership
                    )
                )
            }
        }

        edges.sort(by: Self.sortEdges)

        var connectionCounts: [GraphNodeID: Int] = [:]
        for edge in edges {
            connectionCounts[edge.source, default: 0] += 1
            connectionCounts[edge.target, default: 0] += 1
        }

        var nodes = notes.map { note in
            let id = GraphNodeID.note(note.id)
            return GraphNode(
                id: id,
                kind: .note(note.noteType),
                label: note.title,
                connectionCount: connectionCounts[id, default: 0],
                spaceID: note.spaceID
            )
        }
        nodes.append(contentsOf: includedEntities.map { entity in
            let id = GraphNodeID.entity(entity.id)
            return GraphNode(
                id: id,
                kind: .entity(entity.kind),
                label: entity.name,
                connectionCount: connectionCounts[id, default: 0],
                spaceID: nil
            )
        })
        nodes.append(contentsOf: spaces.map { space in
            let id = GraphNodeID.space(space.id)
            return GraphNode(
                id: id,
                kind: .space,
                label: space.name,
                connectionCount: connectionCounts[id, default: 0],
                spaceID: space.id
            )
        })
        nodes.sort(by: Self.sortNodes)

        return GraphSnapshot(nodes: nodes, edges: edges, generatedAt: Date())
    }

    public func backlinks(noteID: UUID) async throws -> [Backlink] {
        var backlinks: [Backlink] = []
        for note in try await notes.listNotes() where note.id != noteID {
            for link in note.links where link.targetNoteID == noteID {
                backlinks.append(
                    Backlink(
                        sourceNoteID: note.id,
                        sourceTitle: note.title,
                        kind: link.kind
                    )
                )
            }
        }
        return backlinks.sorted {
            if $0.sourceTitle == $1.sourceTitle {
                return $0.sourceNoteID.uuidString < $1.sourceNoteID.uuidString
            }
            return $0.sourceTitle < $1.sourceTitle
        }
    }

    public func entities(noteID: UUID) async throws -> [Entity] {
        try await entities.list()
            .filter { entity in
                entity.sources.contains { $0.noteID == noteID }
            }
            .sorted {
                if $0.name == $1.name {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.name < $1.name
            }
    }

    private static func sortNodes(_ lhs: GraphNode, _ rhs: GraphNode) -> Bool {
        let lhsRank = kindRank(lhs.kind)
        let rhsRank = kindRank(rhs.kind)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        let labelComparison = lhs.label.caseInsensitiveCompare(rhs.label)
        if labelComparison != .orderedSame {
            return labelComparison == .orderedAscending
        }
        return uuidString(lhs.id) < uuidString(rhs.id)
    }

    private static func sortEdges(_ lhs: GraphEdge, _ rhs: GraphEdge) -> Bool {
        let lhsSource = uuidString(lhs.source)
        let rhsSource = uuidString(rhs.source)
        if lhsSource != rhsSource {
            return lhsSource < rhsSource
        }
        let lhsTarget = uuidString(lhs.target)
        let rhsTarget = uuidString(rhs.target)
        if lhsTarget != rhsTarget {
            return lhsTarget < rhsTarget
        }
        return edgeKindDescription(lhs.kind) < edgeKindDescription(rhs.kind)
    }

    private static func kindRank(_ kind: GraphNodeKind) -> Int {
        switch kind {
        case .note:
            0
        case .entity:
            1
        case .space:
            2
        }
    }

    private static func uuidString(_ id: GraphNodeID) -> String {
        switch id {
        case .note(let id), .entity(let id), .space(let id):
            id.uuidString
        }
    }

    private static func edgeKindDescription(_ kind: GraphEdgeKind) -> String {
        switch kind {
        case .link(let linkKind):
            "link.\(linkKind.rawValue)"
        case .entityMention:
            "entityMention"
        case .spaceMembership:
            "spaceMembership"
        }
    }
}
