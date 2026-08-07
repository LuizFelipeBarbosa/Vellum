import Foundation

public struct AgentContext: Codable, Sendable {
    public let noteID: UUID
    public let noteRevision: Int
    public let title: String
    public let canonicalText: String
    public let currentSpaceID: UUID?
    public let spaces: [Space]
    public let otherNotes: [NoteRef]
    /// Tags already assigned to the note being analyzed.
    public let existingTags: [String]
    /// Note IDs already linked from the note being analyzed.
    public let existingLinkTargetIDs: [UUID]
    /// Entity names already sourced from the note being analyzed.
    public let existingEntityNames: [String]

    public init(
        noteID: UUID,
        noteRevision: Int,
        title: String,
        canonicalText: String,
        currentSpaceID: UUID? = nil,
        spaces: [Space] = [],
        otherNotes: [NoteRef] = [],
        existingTags: [String] = [],
        existingLinkTargetIDs: [UUID] = [],
        existingEntityNames: [String] = []
    ) {
        self.noteID = noteID
        self.noteRevision = noteRevision
        self.title = title
        self.canonicalText = canonicalText
        self.currentSpaceID = currentSpaceID
        self.spaces = spaces
        self.otherNotes = otherNotes
        self.existingTags = existingTags
        self.existingLinkTargetIDs = existingLinkTargetIDs
        self.existingEntityNames = existingEntityNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteID = try container.decode(UUID.self, forKey: .noteID)
        noteRevision = try container.decode(Int.self, forKey: .noteRevision)
        title = try container.decode(String.self, forKey: .title)
        canonicalText = try container.decode(String.self, forKey: .canonicalText)
        currentSpaceID = try container.decodeIfPresent(UUID.self, forKey: .currentSpaceID)
        spaces = try container.decode([Space].self, forKey: .spaces)
        otherNotes = try container.decode([NoteRef].self, forKey: .otherNotes)
        existingTags = try container.decodeIfPresent([String].self, forKey: .existingTags) ?? []
        existingLinkTargetIDs = try container.decodeIfPresent(
            [UUID].self,
            forKey: .existingLinkTargetIDs
        ) ?? []
        existingEntityNames = try container.decodeIfPresent(
            [String].self,
            forKey: .existingEntityNames
        ) ?? []
    }
}

public struct AgentProposal: Identifiable, Codable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let basedOnRevision: Int
    public let createdAt: Date
    public let title: String
    public let explanation: String
    public let confidence: Double
    public let operation: AgentOperation
    public var status: ProposalStatus

    public init(
        id: UUID,
        noteID: UUID,
        basedOnRevision: Int,
        createdAt: Date,
        title: String,
        explanation: String,
        confidence: Double,
        operation: AgentOperation,
        status: ProposalStatus
    ) {
        self.id = id
        self.noteID = noteID
        self.basedOnRevision = basedOnRevision
        self.createdAt = createdAt
        self.title = title
        self.explanation = explanation
        self.confidence = confidence
        self.operation = operation
        self.status = status
    }
}

public enum AgentOperation: Codable, Sendable, Equatable {
    case addTag(String)
    case suggestTitle(String)
    case createSummary(String)
    case fileToSpace(spaceName: String, color: SpaceColor)
    case linkNotes(targetNoteID: UUID, kind: LinkKind)
    case extractTask(text: String, pageID: UUID?)
    case extractEntity(name: String, kind: EntityKind, pageID: UUID?, excerpt: String?)
}

public enum ProposalStatus: String, Codable, Sendable {
    case pending
    case accepted
    case rejected
    case stale
}

public struct ActivityEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let noteID: UUID?
    public let createdAt: Date
    public let kind: ActivityKind
    public let message: String

    public init(id: UUID, noteID: UUID?, createdAt: Date, kind: ActivityKind, message: String) {
        self.id = id
        self.noteID = noteID
        self.createdAt = createdAt
        self.kind = kind
        self.message = message
    }
}

public enum ActivityKind: String, Codable, Sendable {
    case noteCreated
    case noteUpdated
    case noteDeleted
    case noteTrashed
    case noteRestored
    case notePurged
    case analysisRequested
    case proposalAccepted
    case proposalRejected
    case proposalMarkedStale
    case noteFiledToSpace
    case notesLinked
    case taskExtracted
    case taskCompleted
    case entityExtracted
    case spaceCreated
    case spaceDeleted
    case questionAnswered
    case workspaceSeeded
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ActivityKind(rawValue: rawValue) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
