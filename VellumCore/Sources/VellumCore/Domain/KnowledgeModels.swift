import Foundation

public struct NoteLink: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let targetNoteID: UUID
    public var kind: LinkKind
    public let createdAt: Date

    public init(id: UUID, targetNoteID: UUID, kind: LinkKind, createdAt: Date) {
        self.id = id
        self.targetNoteID = targetNoteID
        self.kind = kind
        self.createdAt = createdAt
    }
}

public enum LinkKind: String, Codable, Sendable, CaseIterable {
    case mention
    case related
}

public struct Space: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var color: SpaceColor
    public let createdAt: Date
    public var parentID: UUID?

    public init(id: UUID, name: String, color: SpaceColor, createdAt: Date, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.parentID = parentID
    }
}

public enum SpaceColor: String, Codable, Sendable, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case purple
    case pink
    case gray
}

public enum EntityKind: String, Codable, Sendable, CaseIterable {
    case person
    case topic
    case document
}

public struct EntitySource: Codable, Sendable, Equatable, Hashable {
    public let noteID: UUID
    public let pageID: UUID?
    public let excerpt: String?

    public init(noteID: UUID, pageID: UUID?, excerpt: String?) {
        self.noteID = noteID
        self.pageID = pageID
        self.excerpt = excerpt
    }
}

public struct Entity: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var kind: EntityKind
    public var sources: [EntitySource]
    public let createdAt: Date

    public init(id: UUID, name: String, kind: EntityKind, sources: [EntitySource], createdAt: Date) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sources = sources
        self.createdAt = createdAt
    }
}

public struct TaskItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let noteID: UUID
    public let pageID: UUID?
    public var text: String
    public var isDone: Bool
    public let createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID,
        noteID: UUID,
        pageID: UUID?,
        text: String,
        isDone: Bool,
        createdAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.noteID = noteID
        self.pageID = pageID
        self.text = text
        self.isDone = isDone
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public struct NoteRef: Codable, Sendable, Equatable {
    public let id: UUID
    public let title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

public struct NoteSummary: Identifiable, Codable, Sendable {
    public let id: UUID
    public let title: String
    public let noteType: NoteType
    public let spaceID: UUID?
    public let previewText: String
    public let hasInk: Bool
    public let linkCount: Int
    public let updatedAt: Date

    public init(
        id: UUID,
        title: String,
        noteType: NoteType,
        spaceID: UUID?,
        previewText: String,
        hasInk: Bool,
        linkCount: Int,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.noteType = noteType
        self.spaceID = spaceID
        self.previewText = previewText
        self.hasInk = hasInk
        self.linkCount = linkCount
        self.updatedAt = updatedAt
    }
}

public struct SpaceListing: Codable, Sendable {
    public let space: Space
    public let noteCount: Int

    public init(space: Space, noteCount: Int) {
        self.space = space
        self.noteCount = noteCount
    }
}

public struct ActivityDigest: Codable, Sendable {
    public let since: Date
    public let countsByKind: [ActivityKind: Int]
    public let totalAgentActions: Int

    public init(since: Date, countsByKind: [ActivityKind: Int], totalAgentActions: Int) {
        self.since = since
        self.countsByKind = countsByKind
        self.totalAgentActions = totalAgentActions
    }
}
