import Foundation

public struct CanvasRect: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct CanvasSize: Codable, Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct TextBoxContent: Codable, Equatable, Sendable {
    public var text: String
    public var fontSize: Double
    public var color: CodableColor

    public init(text: String, fontSize: Double, color: CodableColor) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
    }
}

public struct ImageContent: Codable, Equatable, Sendable {
    public var assetPath: String
    public var originalPixelSize: CanvasSize
    public var flippedHorizontally: Bool
    public var flippedVertically: Bool

    public init(
        assetPath: String,
        originalPixelSize: CanvasSize,
        flippedHorizontally: Bool = false,
        flippedVertically: Bool = false
    ) {
        self.assetPath = assetPath
        self.originalPixelSize = originalPixelSize
        self.flippedHorizontally = flippedHorizontally
        self.flippedVertically = flippedVertically
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetPath = try container.decode(String.self, forKey: .assetPath)
        originalPixelSize = try container.decode(CanvasSize.self, forKey: .originalPixelSize)
        flippedHorizontally =
            try container.decodeIfPresent(Bool.self, forKey: .flippedHorizontally) ?? false
        flippedVertically =
            try container.decodeIfPresent(Bool.self, forKey: .flippedVertically) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assetPath, forKey: .assetPath)
        try container.encode(originalPixelSize, forKey: .originalPixelSize)
        try container.encode(flippedHorizontally, forKey: .flippedHorizontally)
        try container.encode(flippedVertically, forKey: .flippedVertically)
    }

    private enum CodingKeys: String, CodingKey {
        case assetPath
        case originalPixelSize
        case flippedHorizontally
        case flippedVertically
    }
}

public struct UnknownContent: Equatable, Sendable {
    public let kind: String
    public let payload: JSONValue

    public init(kind: String, payload: JSONValue) {
        self.kind = kind
        self.payload = payload
    }
}

public enum LayerPlacement: String, Codable, Sendable {
    case belowInk
    case aboveInk
}

public struct CanvasElement: Identifiable, Codable, Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case text(TextBoxContent)
        case image(ImageContent)
        case shape(ShapeContent)
        case unknown(UnknownContent)
    }

    public let id: UUID
    public var content: Content
    public var frame: CanvasRect
    public var rotation: Double
    public let createdAt: Date
    public var layerPlacement: LayerPlacement?

    public init(
        id: UUID = UUID(),
        content: Content,
        frame: CanvasRect,
        rotation: Double = 0,
        createdAt: Date = Date(),
        layerPlacement: LayerPlacement? = nil
    ) {
        self.id = id
        self.content = content
        self.frame = frame
        self.rotation = rotation
        self.createdAt = createdAt
        self.layerPlacement = layerPlacement
    }

    public var effectivePlacement: LayerPlacement {
        if let layerPlacement { return layerPlacement }

        switch content {
        case .text:
            return .aboveInk
        case .image, .shape, .unknown:
            return .belowInk
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "text":
            content = .text(try container.decode(TextBoxContent.self, forKey: .text))
        case "image":
            content = .image(try container.decode(ImageContent.self, forKey: .image))
        case "shape":
            do {
                content = .shape(try container.decode(ShapeContent.self, forKey: .shape))
            } catch {
                content = try Self.decodeUnknownContent(kind: kind, from: decoder)
            }
        default:
            content = try Self.decodeUnknownContent(kind: kind, from: decoder)
        }
        frame = try container.decode(CanvasRect.self, forKey: .frame)
        rotation = try container.decode(Double.self, forKey: .rotation)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        if let rawPlacement = try container.decodeIfPresent(String.self, forKey: .layerPlacement) {
            layerPlacement = LayerPlacement(rawValue: rawPlacement)
        } else {
            layerPlacement = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch content {
        case .text(let text):
            try container.encode("text", forKey: .kind)
            try container.encode(text, forKey: .text)
        case .image(let image):
            try container.encode("image", forKey: .kind)
            try container.encode(image, forKey: .image)
        case .shape(let shape):
            try container.encode("shape", forKey: .kind)
            try container.encode(shape, forKey: .shape)
        case .unknown(let unknown):
            try container.encode(unknown.kind, forKey: .kind)
            if unknown.payload != .null {
                var dynamicContainer = encoder.container(keyedBy: AnyCodingKey.self)
                try dynamicContainer.encode(unknown.payload, forKey: AnyCodingKey(unknown.kind))
            }
        }
        try container.encode(frame, forKey: .frame)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(layerPlacement, forKey: .layerPlacement)
    }

    private static func decodeUnknownContent(kind: String, from decoder: Decoder) throws -> Content {
        let dynamicContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        let payload = try dynamicContainer.decodeIfPresent(
            JSONValue.self,
            forKey: AnyCodingKey(kind)
        ) ?? .null
        return .unknown(UnknownContent(kind: kind, payload: payload))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case text
        case image
        case shape
        case frame
        case rotation
        case createdAt
        case layerPlacement
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
