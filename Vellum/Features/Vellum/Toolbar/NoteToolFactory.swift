import PencilKit

enum NoteToolFactory {
    @MainActor
    static func tool(for id: ToolID, preferences: ToolPreferences) -> (any PKTool)? {
        switch id {
        case .pen, .pencil, .highlighter:
            guard let keyPath = id.inkConfigKeyPath else { return nil }
            return inkingTool(preferences[keyPath: keyPath])
        case .eraser:
            switch preferences.eraser.mode {
            case .partial:
                return PKEraserTool(.bitmap, width: CGFloat(preferences.eraser.width))
            case .wholeStroke:
                return PKEraserTool(.vector)
            }
        case .select:
            return nil
        case .text:
            return nil
        }
    }

    @MainActor
    static func inkingTool(_ config: InkToolConfig) -> PKInkingTool {
        let inkType = inkType(for: config.style)
        let configuredRange = widthRange(for: config.style)
        let validRange = inkType.validWidthRange
        let lowerBound = max(configuredRange.lowerBound, Double(validRange.lowerBound))
        let upperBound = min(configuredRange.upperBound, Double(validRange.upperBound))
        let width = min(max(config.width, lowerBound), upperBound)
        let color = config.style == .marker
            ? config.color.uiColor.withAlphaComponent(0.55)
            : config.color.uiColor
        return PKInkingTool(inkType, color: color, width: CGFloat(width))
    }

    static func widthRange(for style: InkStyle) -> ClosedRange<Double> {
        switch style {
        case .pen, .fountainPen, .monoline:
            1...12
        case .pencil, .crayon:
            1...16
        case .marker, .watercolor:
            6...30
        }
    }

    static func validStyles(for tool: ToolID) -> [InkStyle] {
        switch tool {
        case .pen:
            [.pen, .fountainPen, .monoline]
        case .pencil:
            [.pencil, .crayon]
        case .highlighter:
            [.marker, .watercolor]
        case .eraser, .select, .text:
            []
        }
    }

    @MainActor
    private static func inkType(for style: InkStyle) -> PKInkingTool.InkType {
        switch style {
        case .pen: .pen
        case .fountainPen: .fountainPen
        case .monoline: .monoline
        case .pencil: .pencil
        case .crayon: .crayon
        case .marker: .marker
        case .watercolor: .watercolor
        }
    }
}
