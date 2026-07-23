import Foundation

public struct PageBackgroundStyle: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case blank
        case ruled
        case grid
        case dots
    }

    public var kind: Kind
    public var spacing: Double
    public var paperTint: CodableColor?

    public static let spacingRange: ClosedRange<Double> = 16...48
    public static let defaultSpacing: Double = 24
    public static let blank = PageBackgroundStyle(kind: .blank)
    public static let legacyDefault = PageBackgroundStyle(kind: .dots)

    private enum CodingKeys: String, CodingKey {
        case kind
        case spacing
        case paperTint
    }

    public init(
        kind: Kind,
        spacing: Double = Self.defaultSpacing,
        paperTint: CodableColor? = nil
    ) {
        self.kind = kind
        self.spacing = Self.clampedSpacing(spacing)
        self.paperTint = paperTint
    }

    public static func clampedSpacing(_ value: Double) -> Double {
        guard !value.isNaN else { return defaultSpacing }
        if value < spacingRange.lowerBound { return spacingRange.lowerBound }
        if value > spacingRange.upperBound { return spacingRange.upperBound }
        return value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rawKind = try container.decodeIfPresent(String.self, forKey: .kind) {
            kind = Kind(rawValue: rawKind) ?? .blank
        } else {
            kind = .dots
        }
        spacing = Self.clampedSpacing(
            try container.decodeIfPresent(Double.self, forKey: .spacing) ?? Self.defaultSpacing
        )
        paperTint = try container.decodeIfPresent(CodableColor.self, forKey: .paperTint)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(spacing, forKey: .spacing)
        try container.encodeIfPresent(paperTint, forKey: .paperTint)
    }
}

extension PageBackgroundStyle {
    public static let presetTints: [CodableColor] = [
        CodableColor(hex: "#FFFFFF"),
        CodableColor(hex: "#FAF3DC"),
        CodableColor(hex: "#EDECE8"),
        CodableColor(hex: "#23201A"),
    ]

    public static func isDarkTint(_ tint: CodableColor) -> Bool {
        0.2126 * tint.red + 0.7152 * tint.green + 0.0722 * tint.blue < 0.5
    }

    public static func patternInk(forTint tint: CodableColor, opacity: Double) -> CodableColor {
        CodableColor(
            hex: isDarkTint(tint) ? "#E9E3D6" : "#26221B",
            alpha: opacity
        )
    }
}
