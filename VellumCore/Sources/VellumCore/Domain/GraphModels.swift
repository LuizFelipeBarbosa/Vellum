import Foundation

public enum GraphNodeID: Codable, Sendable, Hashable {
    case note(UUID)
    case entity(UUID)
    case space(UUID)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let id = try container.decode(UUID.self, forKey: .id)

        switch type {
        case "note":
            self = .note(id)
        case "entity":
            self = .entity(id)
        case "space":
            self = .space(id)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown graph node type '\(type)'."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .note(let id):
            try container.encode("note", forKey: .type)
            try container.encode(id, forKey: .id)
        case .entity(let id):
            try container.encode("entity", forKey: .type)
            try container.encode(id, forKey: .id)
        case .space(let id):
            try container.encode("space", forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}

public enum GraphNodeKind: Codable, Sendable, Equatable {
    case note(NoteType)
    case entity(EntityKind)
    case space
}

public struct GraphNode: Identifiable, Codable, Sendable, Equatable {
    public let id: GraphNodeID
    public let kind: GraphNodeKind
    public let label: String
    public let connectionCount: Int
    public let spaceID: UUID?

    public init(
        id: GraphNodeID,
        kind: GraphNodeKind,
        label: String,
        connectionCount: Int,
        spaceID: UUID?
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.connectionCount = connectionCount
        self.spaceID = spaceID
    }
}

public enum GraphEdgeKind: Codable, Sendable, Equatable, Hashable {
    case link(LinkKind)
    case entityMention
    case spaceMembership
}

public struct GraphEdge: Codable, Sendable, Equatable, Hashable {
    public let source: GraphNodeID
    public let target: GraphNodeID
    public let kind: GraphEdgeKind

    public init(source: GraphNodeID, target: GraphNodeID, kind: GraphEdgeKind) {
        self.source = source
        self.target = target
        self.kind = kind
    }
}

public struct GraphSnapshot: Codable, Sendable {
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]
    public let generatedAt: Date

    public init(nodes: [GraphNode], edges: [GraphEdge], generatedAt: Date) {
        self.nodes = nodes
        self.edges = edges
        self.generatedAt = generatedAt
    }
}

public struct Backlink: Codable, Sendable, Equatable {
    public let sourceNoteID: UUID
    public let sourceTitle: String
    public let kind: LinkKind

    public init(sourceNoteID: UUID, sourceTitle: String, kind: LinkKind) {
        self.sourceNoteID = sourceNoteID
        self.sourceTitle = sourceTitle
        self.kind = kind
    }
}
