import SwiftUI
import VellumCore

struct ModeToggleRow<Mode: Hashable>: View {
    @Environment(\.vellumWobble) private var vellumWobble

    struct Option {
        let mode: Mode
        let label: String
        let systemImage: String
    }

    let options: [Option]
    let selection: Mode
    var axis: ToolbarDockEdge.Axis = .horizontal
    let onSelect: (Mode) -> Void

    var body: some View {
        let stack = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        stack {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                button(for: option)
            }
        }
        .padding(.horizontal, axis == .vertical ? 10 : 22)
        .padding(.vertical, axis == .vertical ? 22 : 10)
    }

    @ViewBuilder
    private func button(for option: Option) -> some View {
        let isSelected = option.mode == selection
        Button {
            onSelect(option.mode)
        } label: {
            Group {
                if axis == .vertical {
                    Image(systemName: option.systemImage)
                        .frame(width: 24, height: 24)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: option.systemImage)
                        Text(option.label)
                            .font(.vellumSans(13, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
            .foregroundStyle(isSelected ? VellumTheme.accentDark : VellumTheme.mutedDark)
            .background(
                isSelected ? VellumTheme.accent(0.11) : .clear,
                in: OrganicPillShape(variant: 0, smallRadius: axis == .vertical ? 6 : 8, isOrganic: vellumWobble)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct EraserModeRow: View {
    let store: ToolPreferencesStore
    var axis: ToolbarDockEdge.Axis = .horizontal

    var body: some View {
        ModeToggleRow(
            options: [
                .init(
                    mode: EraserMode.partial,
                    label: "Partial",
                    systemImage: "eraser.line.dashed"
                ),
                .init(
                    mode: EraserMode.wholeStroke,
                    label: "Stroke",
                    systemImage: "eraser.fill"
                ),
            ],
            selection: store.preferences.eraser.mode,
            axis: axis,
            onSelect: { mode in
                store.update { $0.eraser.mode = mode }
            }
        )
    }
}

struct SelectionModeRow: View {
    let store: ToolPreferencesStore
    var axis: ToolbarDockEdge.Axis = .horizontal

    var body: some View {
        ModeToggleRow(
            options: [
                .init(
                    mode: SelectionMode.freeform,
                    label: "Freeform",
                    systemImage: "lasso"
                ),
                .init(
                    mode: SelectionMode.boxed,
                    label: "Box",
                    systemImage: "rectangle.dashed"
                ),
            ],
            selection: store.preferences.selection.mode,
            axis: axis,
            onSelect: { mode in
                store.update { $0.selection.mode = mode }
            }
        )
    }
}
