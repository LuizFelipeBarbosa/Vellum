import Foundation

public enum NoteType: String, Codable, Sendable, CaseIterable {
    case note
    case pdf
    case deck
    case image
    case audio
}

public struct Note: Identifiable, Codable, Sendable {
    public static let currentSchemaVersion = 2

    public let id: UUID
    public var schemaVersion: Int
    public var revision: Int
    public var title: String
    public var tags: [String]
    public let createdAt: Date
    public var updatedAt: Date
    public var pages: [NotePage]
    public var noteType: NoteType
    public var spaceID: UUID?
    public var links: [NoteLink]

    public init(
        id: UUID,
        schemaVersion: Int,
        revision: Int,
        title: String,
        tags: [String],
        createdAt: Date,
        updatedAt: Date,
        pages: [NotePage],
        noteType: NoteType = .note,
        spaceID: UUID? = nil,
        links: [NoteLink] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.title = title
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pages = pages
        self.noteType = noteType
        self.spaceID = spaceID
        self.links = links
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        revision = try container.decode(Int.self, forKey: .revision)
        title = try container.decode(String.self, forKey: .title)
        tags = try container.decode([String].self, forKey: .tags)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pages = try container.decode([NotePage].self, forKey: .pages)
        noteType = try container.decodeIfPresent(NoteType.self, forKey: .noteType) ?? .note
        spaceID = try container.decodeIfPresent(UUID.self, forKey: .spaceID)
        links = try container.decodeIfPresent([NoteLink].self, forKey: .links) ?? []
    }
}

public struct NotePage: Identifiable, Codable, Sendable {
    public let id: UUID
    public var order: Int
    public var plainText: String
    public var drawingAssetPath: String
    public var background: PageBackground

    public init(
        id: UUID,
        order: Int,
        plainText: String,
        drawingAssetPath: String,
        background: PageBackground
    ) {
        self.id = id
        self.order = order
        self.plainText = plainText
        self.drawingAssetPath = drawingAssetPath
        self.background = background
    }
}

public enum PageBackground: String, Codable, Sendable {
    case blank
    case ruled
    case grid
    case pdf
    case image
}
