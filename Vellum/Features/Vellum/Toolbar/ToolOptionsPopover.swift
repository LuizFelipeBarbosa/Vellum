import SwiftUI
import UIKit
import VellumCore

struct ToolOptionsPopover: View {
    let tool: ToolID
    let store: ToolPreferencesStore

    var body: some View {
        Group {
            switch tool {
            case .pen, .pencil, .highlighter:
                InkToolOptionsView(tool: tool, store: store)
            case .eraser:
                EraserOptionsView(store: store)
            case .select:
                EmptyView()
            case .text:
                TextOptionsView(store: store)
            }
        }
    }
}

struct InkToolOptionsView: View {
    let tool: ToolID
    let store: ToolPreferencesStore

    @Environment(\.inkDisplayStyle) private var inkDisplayStyle

    var body: some View {
        let config = tool.inkConfigKeyPath.map { store.preferences[keyPath: $0] }
            ?? store.preferences.pen
        let widthRange = NoteToolFactory.widthRange(for: config.style)
        let currentLevel = ToolWidthLevels.level(forWidth: config.width, in: widthRange)
        let presetWidths = [
            widthRange.lowerBound,
            (widthRange.lowerBound + widthRange.upperBound) / 2,
            widthRange.upperBound,
        ]

        VStack(alignment: .leading, spacing: 14) {
            Text("\(tool.displayName) Options")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)

            OptionsSectionCaption("Style")

            Picker("Style", selection: styleBinding) {
                ForEach(
                    Array(NoteToolFactory.validStyles(for: tool).enumerated()),
                    id: \.offset
                ) { _, style in
                    Text(style.shortLabel)
                        .tag(style)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Ink style")

            OptionsDivider()

            HStack(spacing: 6) {
                OptionsSectionCaption("Width")

                Text("Level \(currentLevel)")
                    .font(.system(size: 12))
                    .foregroundStyle(VellumTheme.mutedDark)
            }

            HStack(spacing: 12) {
                Slider(value: levelBinding, in: 1...10, step: 1)
                    .accessibilityLabel("Stroke width")
                    .accessibilityValue("Level \(currentLevel)")

                Capsule()
                    .fill(displayedColor(config.color))
                    .frame(width: 34, height: strokePreviewHeight(for: config))
                    .frame(width: 38, height: 16)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 20) {
                ForEach(Array(presetWidths.enumerated()), id: \.offset) { index, width in
                    Button {
                        store.setWidth(
                            ToolWidthLevels.width(
                                forLevel: ToolWidthLevels.level(
                                    forWidth: width,
                                    in: widthRange
                                ),
                                in: widthRange
                            ),
                            for: tool
                        )
                    } label: {
                        Circle()
                            .fill(VellumTheme.mutedDark)
                            .frame(
                                width: CGFloat(4 + (index * 2)),
                                height: CGFloat(4 + (index * 2))
                            )
                            .frame(width: 28, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set width \(Int(width.rounded())) points")
                }
            }

            OptionsDivider()

            OptionsSectionCaption("Color")

            ColorSwatchGrid(
                favorites: store.preferences.favorites,
                selectedColor: config.color,
                onSelect: { color in
                    store.setColor(color, for: tool)
                }
            )

            HStack(spacing: 12) {
                ColorPicker(
                    "Custom",
                    selection: colorBinding,
                    supportsOpacity: false
                )
                .accessibilityLabel("Custom ink color")

                Spacer()

                Button {
                    store.addFavorite(config.color)
                } label: {
                    Image(
                        systemName: store.preferences.favorites.contains(config.color)
                            ? "star.fill"
                            : "star"
                    )
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(store.preferences.favorites.contains(config.color))
                .accessibilityLabel("Add to Favorites")
                .accessibilityValue(
                    store.preferences.favorites.contains(config.color)
                        ? "Already a favorite"
                        : config.color.hexString
                )
            }
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .background(VellumTheme.popover)
    }

    private var styleBinding: Binding<InkStyle> {
        Binding(
            get: {
                guard let keyPath = tool.inkConfigKeyPath else {
                    return store.preferences.pen.style
                }
                return store.preferences[keyPath: keyPath].style
            },
            set: { style in
                store.setStyle(style, for: tool)
            }
        )
    }

    private var levelBinding: Binding<Double> {
        Binding(
            get: {
                let config = tool.inkConfigKeyPath.map { store.preferences[keyPath: $0] }
                    ?? store.preferences.pen
                let widthRange = NoteToolFactory.widthRange(for: config.style)
                return Double(
                    ToolWidthLevels.level(forWidth: config.width, in: widthRange)
                )
            },
            set: { newValue in
                let config = tool.inkConfigKeyPath.map { store.preferences[keyPath: $0] }
                    ?? store.preferences.pen
                let widthRange = NoteToolFactory.widthRange(for: config.style)
                store.setWidth(
                    ToolWidthLevels.width(
                        forLevel: Int(newValue.rounded()),
                        in: widthRange
                    ),
                    for: tool
                )
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                guard let keyPath = tool.inkConfigKeyPath else {
                    return displayedColor(store.preferences.pen.color)
                }
                return displayedColor(store.preferences[keyPath: keyPath].color)
            },
            set: { color in
                store.setColor(
                    InkAppearance.storedColor(
                        for: UIColor(color),
                        style: inkDisplayStyle
                    ),
                    for: tool
                )
            }
        )
    }

    private func displayedColor(_ color: CodableColor) -> Color {
        Color(InkAppearance.displayColor(for: color, style: inkDisplayStyle))
    }

    private func strokePreviewHeight(for config: InkToolConfig) -> CGFloat {
        let widthRange = NoteToolFactory.widthRange(for: config.style)
        let span = widthRange.upperBound - widthRange.lowerBound
        let normalizedWidth = (config.width - widthRange.lowerBound) / span
        let clampedWidth = min(max(normalizedWidth, 0), 1)

        return CGFloat(2 + (clampedWidth * 8))
    }
}

struct EraserOptionsView: View {
    let store: ToolPreferencesStore

    private let widthRange: ClosedRange<Double> = 8...60

    var body: some View {
        let currentLevel = ToolWidthLevels.level(
            forWidth: store.preferences.eraser.width,
            in: widthRange
        )

        VStack(alignment: .leading, spacing: 14) {
            Text("Eraser Options")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)

            if store.preferences.eraser.mode == .partial {
                HStack(spacing: 6) {
                    OptionsSectionCaption("Width")

                    Text("Level \(currentLevel)")
                        .font(.system(size: 12))
                        .foregroundStyle(VellumTheme.mutedDark)
                }

                HStack(spacing: 16) {
                    Slider(value: levelBinding, in: 1...10, step: 1)
                        .accessibilityLabel("Eraser width")
                        .accessibilityValue("Level \(currentLevel)")

                    Circle()
                        .stroke(VellumTheme.mutedDark, lineWidth: 2)
                        .frame(width: eraserPreviewSize, height: eraserPreviewSize)
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                }
            } else {
                Text("Whole-stroke eraser removes entire strokes.")
                    .font(.system(size: 12))
                    .foregroundStyle(VellumTheme.mutedDark)
            }
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .background(VellumTheme.popover)
    }

    private var levelBinding: Binding<Double> {
        Binding(
            get: {
                Double(
                    ToolWidthLevels.level(
                        forWidth: store.preferences.eraser.width,
                        in: widthRange
                    )
                )
            },
            set: { newValue in
                store.update { preferences in
                    preferences.eraser.width = ToolWidthLevels.width(
                        forLevel: Int(newValue.rounded()),
                        in: widthRange
                    )
                }
            }
        )
    }

    private var eraserPreviewSize: CGFloat {
        let span = widthRange.upperBound - widthRange.lowerBound
        let normalizedWidth = (store.preferences.eraser.width - widthRange.lowerBound) / span
        let clampedWidth = min(max(normalizedWidth, 0), 1)
        return CGFloat(12 + (clampedWidth * 28))
    }
}

struct TextOptionsView: View {
    let store: ToolPreferencesStore

    @Environment(\.inkDisplayStyle) private var inkDisplayStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Text Options")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)

            OptionsSectionCaption("Size")

            HStack(spacing: 16) {
                Slider(value: fontSizeBinding, in: 10...48)
                    .accessibilityLabel("Text size")
                    .accessibilityValue(
                        "\(Int(store.preferences.text.fontSize.rounded())) points"
                    )

                Text("Aa")
                    .font(.system(size: store.preferences.text.fontSize))
                    .foregroundStyle(
                        Color(
                            InkAppearance.displayColor(
                                for: store.preferences.text.color,
                                style: inkDisplayStyle
                            )
                        )
                    )
                    .frame(width: 54, height: 54)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }

            OptionsDivider()

            OptionsSectionCaption("Color")

            ColorSwatchGrid(
                favorites: store.preferences.favorites,
                selectedColor: store.preferences.text.color,
                onSelect: { color in
                    store.update { preferences in
                        preferences.text.color = color
                    }
                }
            )
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .background(VellumTheme.popover)
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { store.preferences.text.fontSize },
            set: { fontSize in
                store.update { preferences in
                    preferences.text.fontSize = fontSize
                }
            }
        )
    }
}

struct ColorSwatchGrid: View {
    let favorites: [CodableColor]
    let selectedColor: CodableColor
    let onSelect: (CodableColor) -> Void

    @Environment(\.inkDisplayStyle) private var inkDisplayStyle

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 6
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(swatches.enumerated()), id: \.offset) { _, swatch in
                Button {
                    onSelect(swatch)
                } label: {
                    Circle()
                        .fill(
                            Color(
                                InkAppearance.displayColor(
                                    for: swatch,
                                    style: inkDisplayStyle
                                )
                            )
                        )
                        .frame(width: 24, height: 24)
                        .overlay {
                            Circle()
                                .stroke(
                                    swatch == selectedColor ? VellumTheme.accent : .clear,
                                    lineWidth: 2
                                )
                                .padding(-4)
                        }
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(swatch.hexString)")
            }
        }
    }

    private var swatches: [CodableColor] {
        var swatches = ToolPreferences.defaultFavorites
        for color in favorites where !swatches.contains(color) {
            swatches.append(color)
        }
        return swatches
    }
}

struct OptionsSectionCaption: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(VellumTheme.mutedDark)
    }
}

struct OptionsDivider: View {
    var body: some View {
        Rectangle()
            .fill(VellumTheme.ink(0.12))
            .frame(height: 1)
    }
}
