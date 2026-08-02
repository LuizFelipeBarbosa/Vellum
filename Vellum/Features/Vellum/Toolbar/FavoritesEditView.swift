import SwiftUI
import UIKit
import VellumCore

struct FavoritesEditView: View {
    let store: ToolPreferencesStore
    @Environment(\.inkDisplayStyle) private var inkDisplayStyle
    @State private var colorToAdd: Color = .black

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Favorites")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VellumTheme.ink)

                Spacer()

                EditButton()
                    .accessibilityLabel("Edit favorites")
            }

            List {
                ForEach(store.preferences.favorites.indices, id: \.self) { index in
                    let color = store.preferences.favorites[index]

                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(InkAppearance.displayColor(
                                for: color,
                                style: inkDisplayStyle
                            )))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle()
                                    .stroke(VellumTheme.ink(0.12), lineWidth: 1)
                            }
                            .accessibilityHidden(true)

                        Text(color.hexString)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(VellumTheme.mutedDark)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Favorite color \(color.hexString)")
                    .listRowBackground(VellumTheme.popover)
                }
                .onMove { from, to in
                    store.moveFavorites(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    store.removeFavorite(at: offsets)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: 250)
            .background(VellumTheme.popover)

            HStack(spacing: 12) {
                ColorPicker(
                    "Add color",
                    selection: $colorToAdd,
                    supportsOpacity: false
                )
                .accessibilityLabel("Color to add")

                Button("Add") {
                    store.addFavorite(InkAppearance.storedColor(
                        for: UIColor(colorToAdd),
                        style: inkDisplayStyle
                    ))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add color to favorites")
            }

            Button("Reset to Defaults") {
                store.resetFavorites()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .accessibilityLabel("Reset favorites to defaults")
        }
        .padding(18)
        .frame(width: 320, alignment: .leading)
        .frame(maxHeight: 420)
        .background(VellumTheme.popover)
    }
}
