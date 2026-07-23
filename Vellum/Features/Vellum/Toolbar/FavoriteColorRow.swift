import SwiftUI
import VellumCore

struct FavoriteColorRow: View {
    let store: ToolPreferencesStore
    let activeInkTool: ToolID?
    var axis: ToolbarDockEdge.Axis = .horizontal
    var onRequestOptions: () -> Void
    var onRequestFavoritesEditor: () -> Void

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
                .frame(height: 292)
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
                    .fill(activeInkConfig.color.swiftUIColor)
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
                .fill(color.swiftUIColor)
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
}
