import Foundation
import SwiftUI
import UIKit
import VellumCore

enum ToolID: String, Codable, CaseIterable, Identifiable, Sendable {
    case pen
    case pencil
    case highlighter
    case eraser
    case select
    case text

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pen: "Pen"
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .select: "Select"
        case .text: "Text"
        }
    }

    var isInkTool: Bool {
        switch self {
        case .pen, .pencil, .highlighter:
            true
        case .eraser, .select, .text:
            false
        }
    }

    var inkConfigKeyPath: WritableKeyPath<ToolPreferences, InkToolConfig>? {
        switch self {
        case .pen: \ToolPreferences.pen
        case .pencil: \ToolPreferences.pencil
        case .highlighter: \ToolPreferences.highlighter
        case .eraser, .select, .text: nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ToolID(rawValue: (try? container.decode(String.self)) ?? "") ?? .pen
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum InkStyle: String, Codable, CaseIterable, Sendable {
    case pen
    case fountainPen
    case monoline
    case pencil
    case crayon
    case marker
    case watercolor

    var shortLabel: String {
        switch self {
        case .pen: "Pen"
        case .fountainPen: "Fountain"
        case .monoline: "Monoline"
        case .pencil: "Pencil"
        case .crayon: "Crayon"
        case .marker: "Marker"
        case .watercolor: "Watercolor"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = InkStyle(rawValue: (try? container.decode(String.self)) ?? "") ?? .pen
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum EraserMode: String, Codable, Sendable {
    case partial
    case wholeStroke

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = EraserMode(rawValue: (try? container.decode(String.self)) ?? "") ?? .partial
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum SelectionMode: String, Codable, Sendable {
    case freeform
    case boxed

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = SelectionMode(rawValue: (try? container.decode(String.self)) ?? "") ?? .freeform
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct InkToolConfig: Codable, Equatable, Sendable {
    var style: InkStyle
    var color: CodableColor
    var width: Double
}

struct EraserConfig: Codable, Equatable, Sendable {
    var mode: EraserMode
    var width: Double
}

struct SelectionConfig: Codable, Equatable, Sendable {
    var mode: SelectionMode
}

struct TextConfig: Codable, Equatable, Sendable {
    var fontSize: Double
    var color: CodableColor
}

struct ToolPreferences: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var pen: InkToolConfig
    var pencil: InkToolConfig
    var highlighter: InkToolConfig
    var eraser: EraserConfig
    var selection: SelectionConfig
    var text: TextConfig
    var favorites: [CodableColor]
    var lastSelectedTool: ToolID
    var isToolbarCollapsed: Bool

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case pen
        case pencil
        case highlighter
        case eraser
        case selection
        case text
        case favorites
        case lastSelectedTool
        case isToolbarCollapsed
    }

    init(
        schemaVersion: Int,
        pen: InkToolConfig,
        pencil: InkToolConfig,
        highlighter: InkToolConfig,
        eraser: EraserConfig,
        selection: SelectionConfig,
        text: TextConfig,
        favorites: [CodableColor],
        lastSelectedTool: ToolID,
        isToolbarCollapsed: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.pen = pen
        self.pencil = pencil
        self.highlighter = highlighter
        self.eraser = eraser
        self.selection = selection
        self.text = text
        self.favorites = favorites
        self.lastSelectedTool = lastSelectedTool
        self.isToolbarCollapsed = isToolbarCollapsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ToolPreferences.default

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? defaults.schemaVersion
        pen = try Self.decodeInkConfig(from: container, forKey: .pen, default: defaults.pen)
        pencil = try Self.decodeInkConfig(
            from: container,
            forKey: .pencil,
            default: defaults.pencil
        )
        highlighter = try Self.decodeInkConfig(
            from: container,
            forKey: .highlighter,
            default: defaults.highlighter
        )
        eraser = try Self.decodeEraserConfig(
            from: container,
            forKey: .eraser,
            default: defaults.eraser
        )
        selection = try Self.decodeSelectionConfig(
            from: container,
            forKey: .selection,
            default: defaults.selection
        )
        text = try Self.decodeTextConfig(from: container, forKey: .text, default: defaults.text)
        favorites = try container.decodeIfPresent([CodableColor].self, forKey: .favorites)
            ?? defaults.favorites
        let lastSelectedToolRawValue = try container.decodeIfPresent(
            String.self,
            forKey: .lastSelectedTool
        ) ?? defaults.lastSelectedTool.rawValue
        lastSelectedTool = ToolID(rawValue: lastSelectedToolRawValue)
            ?? defaults.lastSelectedTool
        isToolbarCollapsed = try container.decodeIfPresent(
            Bool.self,
            forKey: .isToolbarCollapsed
        ) ?? defaults.isToolbarCollapsed
    }

    static let `default` = ToolPreferences(
        schemaVersion: 1,
        pen: InkToolConfig(style: .pen, color: CodableColor(hex: "#26221B"), width: 4),
        pencil: InkToolConfig(
            style: .pencil,
            color: CodableColor(hex: "#5B564C"),
            width: 5
        ),
        highlighter: InkToolConfig(
            style: .marker,
            color: CodableColor(hex: "#E3B341"),
            width: 12
        ),
        eraser: EraserConfig(mode: .partial, width: 24),
        selection: SelectionConfig(mode: .freeform),
        text: TextConfig(fontSize: 17, color: CodableColor(hex: "#26221B")),
        favorites: defaultFavorites,
        lastSelectedTool: .pen,
        isToolbarCollapsed: false
    )

    static let defaultFavorites = [
        CodableColor(hex: "#26221B"),
        CodableColor(hex: "#5B564C"),
        CodableColor(hex: "#9A6B35"),
        CodableColor(hex: "#B98A4E"),
        CodableColor(hex: "#4E6E58"),
        CodableColor(hex: "#4F7470"),
        CodableColor(hex: "#586E82"),
        CodableColor(hex: "#6E5E7A"),
        CodableColor(hex: "#955B52"),
        CodableColor(hex: "#936B76"),
        CodableColor(hex: "#E3B341"),
        CodableColor(hex: "#D07B3A"),
    ]

    private static func decodeInkConfig(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        default defaultConfig: InkToolConfig
    ) throws -> InkToolConfig {
        let payload = try container.decodeIfPresent(InkToolConfigPayload.self, forKey: key)
        return InkToolConfig(
            style: payload.flatMap { $0.style.flatMap(InkStyle.init(rawValue:)) }
                ?? defaultConfig.style,
            color: payload?.color ?? defaultConfig.color,
            width: payload?.width ?? defaultConfig.width
        )
    }

    private static func decodeEraserConfig(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        default defaultConfig: EraserConfig
    ) throws -> EraserConfig {
        let payload = try container.decodeIfPresent(EraserConfigPayload.self, forKey: key)
        return EraserConfig(
            mode: payload.flatMap { $0.mode.flatMap(EraserMode.init(rawValue:)) }
                ?? defaultConfig.mode,
            width: payload?.width ?? defaultConfig.width
        )
    }

    private static func decodeSelectionConfig(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        default defaultConfig: SelectionConfig
    ) throws -> SelectionConfig {
        let payload = try container.decodeIfPresent(SelectionConfigPayload.self, forKey: key)
        return SelectionConfig(
            mode: payload.flatMap { $0.mode.flatMap(SelectionMode.init(rawValue:)) }
                ?? defaultConfig.mode
        )
    }

    private static func decodeTextConfig(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        default defaultConfig: TextConfig
    ) throws -> TextConfig {
        let payload = try container.decodeIfPresent(TextConfigPayload.self, forKey: key)
        return TextConfig(
            fontSize: payload?.fontSize ?? defaultConfig.fontSize,
            color: payload?.color ?? defaultConfig.color
        )
    }
}

private struct InkToolConfigPayload: Decodable {
    let style: String?
    let color: CodableColor?
    let width: Double?
}

private struct EraserConfigPayload: Decodable {
    let mode: String?
    let width: Double?
}

private struct SelectionConfigPayload: Decodable {
    let mode: String?
}

private struct TextConfigPayload: Decodable {
    let fontSize: Double?
    let color: CodableColor?
}

extension CodableColor {
    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(_ uiColor: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            self.init(red: 0, green: 0, blue: 0, alpha: 1)
            return
        }
        self.init(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }
}
