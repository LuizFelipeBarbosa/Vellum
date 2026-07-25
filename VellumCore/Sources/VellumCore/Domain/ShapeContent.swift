import Foundation

public struct CanvasPoint: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ShapeContent: Equatable, Sendable {
    public enum Geometry: Equatable, Sendable {
        /// Vertices in unit coordinates relative to the element frame (nominally 0...1 per axis;
        /// values slightly outside are legal mid-edit). 2 vertices + isClosed == false → straight line.
        case polyline(vertices: [CanvasPoint], isClosed: Bool)
        /// Ellipse inscribed in the element frame; tilt lives in element.rotation.
        case ellipse
    }

    public var geometry: Geometry
    public var strokeColor: CodableColor
    public var strokeWidth: Double

    public init(geometry: Geometry, strokeColor: CodableColor, strokeWidth: Double) {
        self.geometry = geometry
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }
}

extension ShapeContent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "polyline":
            geometry = .polyline(
                vertices: try container.decode([CanvasPoint].self, forKey: .vertices),
                isClosed: try container.decode(Bool.self, forKey: .isClosed)
            )
        case "ellipse":
            geometry = .ellipse
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unrecognized shape geometry type '\(type)'."
            )
        }
        strokeColor = try container.decode(CodableColor.self, forKey: .strokeColor)
        strokeWidth = try container.decode(Double.self, forKey: .strokeWidth)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch geometry {
        case .polyline(let vertices, let isClosed):
            try container.encode("polyline", forKey: .type)
            try container.encode(vertices, forKey: .vertices)
            try container.encode(isClosed, forKey: .isClosed)
        case .ellipse:
            try container.encode("ellipse", forKey: .type)
        }
        try container.encode(strokeColor, forKey: .strokeColor)
        try container.encode(strokeWidth, forKey: .strokeWidth)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case vertices
        case isClosed
        case strokeColor
        case strokeWidth
    }
}
