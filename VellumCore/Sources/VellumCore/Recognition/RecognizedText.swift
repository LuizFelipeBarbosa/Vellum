import Foundation

public struct RecognizedLine: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case ink
        case typed
    }

    public var text: String
    public var rect: CanvasRect
    public var confidence: Double
    public var source: Source

    public init(text: String, rect: CanvasRect, confidence: Double, source: Source) {
        self.text = text
        self.rect = rect
        self.confidence = confidence
        self.source = source
    }
}

public struct RecognizedPageText: Codable, Sendable, Equatable {
    public var pageID: UUID
    public var pageIndex: Int
    public var lines: [RecognizedLine]
    public var plainText: String

    public init(pageID: UUID, pageIndex: Int, lines: [RecognizedLine], plainText: String) {
        self.pageID = pageID
        self.pageIndex = pageIndex
        self.lines = lines
        self.plainText = plainText
    }
}

public struct RecognizedNoteText: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var inputFingerprint: String
    public var generatedAt: Date
    public var pages: [RecognizedPageText]

    public init(
        schemaVersion: Int,
        inputFingerprint: String,
        generatedAt: Date,
        pages: [RecognizedPageText]
    ) {
        self.schemaVersion = schemaVersion
        self.inputFingerprint = inputFingerprint
        self.generatedAt = generatedAt
        self.pages = pages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? Self.currentSchemaVersion
        inputFingerprint = try container.decodeIfPresent(
            String.self,
            forKey: .inputFingerprint
        ) ?? ""
        generatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .generatedAt
        ) ?? Date(timeIntervalSince1970: 0)
        pages = try container.decodeIfPresent(
            [RecognizedPageText].self,
            forKey: .pages
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(inputFingerprint, forKey: .inputFingerprint)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(pages, forKey: .pages)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case inputFingerprint
        case generatedAt
        case pages
    }
}

public enum RecognitionSidecar {
    public static let relativePath = "derived/recognition.json"
}
