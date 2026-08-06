import SwiftUI
import VellumCore

struct FavoriteColorRow: View {
    let store: ToolPreferencesStore
    let activeInkTool: ToolID?
    var axis: ToolbarDockEdge.Axis = .horizontal
    var availableLength: CGFloat? = nil
    var onRequestOptions: () -> Void
    var onRequestFavoritesEditor: () -> Void

    @Environment(\.inkDisplayStyle) private var inkDisplayStyle

    var body: some View {
        let stack = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: ToolbarMetrics.itemSpacing))
            : AnyLayout(HStackLayout(spacing: ToolbarMetrics.itemSpacing))
        stack {
            if axis == .vertical {
                ScrollView(.vertical) {
                    VStack(spacing: ToolbarMetrics.favoritesDotSpacing) {
                        ForEach(
                            Array(store.preferences.favorites.enumerated()),
                            id: \.offset
                        ) { _, color in
                            colorDot(color)
                        }
                    }
                    .padding(ToolbarMetrics.favoritesInnerPadding)
                }
                .scrollIndicators(.hidden)
                .frame(height: stripHeight)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: ToolbarMetrics.favoritesDotSpacing) {
                        ForEach(
                            Array(store.preferences.favorites.enumerated()),
                            id: \.offset
                        ) { _, color in
                            colorDot(color)
                        }
                    }
                    .padding(ToolbarMetrics.favoritesInnerPadding)
                }
                .scrollIndicators(.hidden)
                .frame(width: ToolbarMetrics.favoritesStripCap)
            }

            Button {
                onRequestFavoritesEditor()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 17, height: 17)
                    .overlay {
                        Circle()
                            .stroke(VellumTheme.mutedDark, lineWidth: 1)
                    }
            }
            .accessibilityLabel("Add favorite color")

            VellumDashedRule(axis: axis == .vertical ? .horizontal : .vertical)
                .stroke(
                    VellumTheme.ink(0.2),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                )
                .frame(
                    width: axis == .vertical ? ToolbarMetrics.dividerLength : ToolbarMetrics.dividerThickness,
                    height: axis == .vertical ? ToolbarMetrics.dividerThickness : ToolbarMetrics.dividerLength
                )

            Button {
                onRequestOptions()
            } label: {
                Capsule()
                    .fill(displayColor(activeInkConfig.color))
                    .frame(width: 28, height: strokeIndicatorHeight)
                    .frame(width: 32, height: 24)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stroke width")
            .accessibilityValue("\(Int(activeInkConfig.width.rounded())) points")
        }
        .buttonStyle(.plain)
        .foregroundStyle(VellumTheme.mutedDark)
        .padding(.horizontal, axis == .vertical ? ToolbarMetrics.crossPadding : ToolbarMetrics.endPadding)
        .padding(.vertical, axis == .vertical ? ToolbarMetrics.endPadding : ToolbarMetrics.crossPadding)
    }

    // Non-strip chrome extent is derived in ToolbarMetrics.verticalNonStripAllowance.
    private var stripHeight: CGFloat {
        min(
            ToolbarMetrics.favoritesStripCap,
            max(
                ToolbarMetrics.favoritesStripMin,
                (availableLength ?? .infinity) - ToolbarMetrics.verticalNonStripAllowance
            )
        )
    }

    private var resolvedInkTool: ToolID {
        activeInkTool ?? .pen
    }

    private var activeInkConfig: InkToolConfig {
        guard let keyPath = resolvedInkTool.inkConfigKeyPath else {
            return store.preferences.pen
        }
        return store.preferences[keyPath: keyPath]
    }

    private var strokeIndicatorHeight: CGFloat {
        let widthRange = NoteToolFactory.widthRange(for: activeInkConfig.style)
        let span = widthRange.upperBound - widthRange.lowerBound
        let normalizedWidth = (activeInkConfig.width - widthRange.lowerBound) / span
        let clampedWidth = min(max(normalizedWidth, 0), 1)

        // Map each ink style's supported width range linearly into a 2–8pt preview.
        return CGFloat(2 + (clampedWidth * 6))
    }

    private func colorDot(_ color: CodableColor) -> some View {
        Button {
            store.setColor(color, for: resolvedInkTool)
        } label: {
            VellumBlobDot(color: displayColor(color), size: 17)
                .overlay {
                    Circle()
                        .stroke(
                            activeInkConfig.color == color ? VellumTheme.accent : .clear,
                            lineWidth: 2
                        )
                        .padding(-4)
                }
        }
        .accessibilityLabel("Color \(color.hexString)")
        .contextMenu {
            Button("Remove from Favorites", role: .destructive) {
                guard let index = store.preferences.favorites.firstIndex(of: color) else {
                    return
                }
                store.removeFavorite(at: IndexSet(integer: index))
            }
            .accessibilityLabel("Remove from Favorites")
        }
    }

    private func displayColor(_ color: CodableColor) -> Color {
        Color(InkAppearance.displayColor(for: color, style: inkDisplayStyle))
    }
}
