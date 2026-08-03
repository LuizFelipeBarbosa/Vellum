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

    // Approximate height of everything in the vertical toolbar other than the
    // favorites strip itself: tools section (undo/redo, 6 tool buttons, insert,
    // paper options, collapse) + dividers + edit/options buttons + paddings.
    private static let verticalChromeAllowance: CGFloat = 580

    var body: some View {
        let stack = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: 14))
            : AnyLayout(HStackLayout(spacing: 14))
        stack {
            if axis == .vertical {
                ScrollView(.vertical) {
                    VStack(spacing: 12) {
                        ForEach(
                            Array(store.preferences.favorites.enumerated()),
                            id: \.offset
                        ) { _, color in
                            colorDot(color)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.hidden)
                .frame(height: stripHeight)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(
                            Array(store.preferences.favorites.enumerated()),
                            id: \.offset
                        ) { _, color in
                            colorDot(color)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.hidden)
                .frame(width: 292)
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

            Rectangle()
                .fill(VellumTheme.ink(0.12))
                .frame(
                    width: axis == .vertical ? 22 : 1,
                    height: axis == .vertical ? 1 : 22
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
        .padding(.horizontal, axis == .vertical ? 10 : 22)
        .padding(.vertical, axis == .vertical ? 22 : 10)
    }

    private var stripHeight: CGFloat {
        min(292, max(120, (availableLength ?? .infinity) - Self.verticalChromeAllowance))
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
            Circle()
                .fill(displayColor(color))
                .frame(width: 17, height: 17)
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
