import Foundation

public struct AskContext: Sendable {
    public let sources: [AskSource]

    public init(sources: [AskSource]) {
        self.sources = sources
    }
}

public struct AskSource: Sendable {
    public let noteID: UUID
    public let title: String
    public let noteType: NoteType
    public let pages: [AskPage]

    public init(noteID: UUID, title: String, noteType: NoteType, pages: [AskPage]) {
        self.noteID = noteID
        self.title = title
        self.noteType = noteType
        self.pages = pages
    }
}

public struct AskPage: Sendable {
    public let pageID: UUID
    public let plainText: String

    public init(pageID: UUID, plainText: String) {
        self.pageID = pageID
        self.plainText = plainText
    }
}

public enum AskSegment: Codable, Sendable, Equatable {
    case text(String, emphasized: Bool)
    case citation(index: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case emphasized
        case index
    }

    private enum SegmentType: String, Codable {
        case text
        case citation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeValue = try container.decode(String.self, forKey: .type)
        guard let type = SegmentType(rawValue: typeValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown ask segment type '\(typeValue)'."
            )
        }

        switch type {
        case .text:
            self = .text(
                try container.decode(String.self, forKey: .text),
                emphasized: try container.decode(Bool.self, forKey: .emphasized)
            )
        case .citation:
            self = .citation(index: try container.decode(Int.self, forKey: .index))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text, let emphasized):
            try container.encode(SegmentType.text.rawValue, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(emphasized, forKey: .emphasized)
        case .citation(let index):
            try container.encode(SegmentType.citation.rawValue, forKey: .type)
            try container.encode(index, forKey: .index)
        }
    }
}

public struct Citation: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let index: Int
    public let noteID: UUID
    public let pageID: UUID?
    public let noteTitle: String
    public let noteType: NoteType
    public let excerpt: String

    public init(
        id: UUID,
        index: Int,
        noteID: UUID,
        pageID: UUID?,
        noteTitle: String,
        noteType: NoteType,
        excerpt: String
    ) {
        self.id = id
        self.index = index
        self.noteID = noteID
        self.pageID = pageID
        self.noteTitle = noteTitle
        self.noteType = noteType
        self.excerpt = excerpt
    }
}

public struct AskAnswer: Codable, Sendable {
    public let question: String
    public let segments: [AskSegment]
    public let citations: [Citation]
    public let followUps: [String]
    public let answeredAt: Date

    public init(
        question: String,
        segments: [AskSegment],
        citations: [Citation],
        followUps: [String],
        answeredAt: Date
    ) {
        self.question = question
        self.segments = segments
        self.citations = citations
        self.followUps = followUps
        self.answeredAt = answeredAt
    }
}

public protocol AskAnswering: Sendable {
    func answer(question: String, context: AskContext) async throws -> AskAnswer
}
