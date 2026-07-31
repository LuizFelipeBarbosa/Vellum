import SwiftUI

enum PaneGhostIntent {
    case split
    case alreadyOpen
    case refused
}

struct PaneGhostView: View {
    let title: String
    let spaceColor: Color?
    let intent: PaneGhostIntent

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(fillColor)

            stroke

            label
                .padding(18)
        }
        .clipped()
        .allowsHitTesting(false)
    }

    private var fillColor: Color {
        switch intent {
        case .split, .refused:
            VellumTheme.paper
        case .alreadyOpen:
            VellumTheme.accent(0.12)
        }
    }

    @ViewBuilder
    private var stroke: some View {
        switch intent {
        case .split:
            RoundedRectangle(cornerRadius: 8)
                .stroke(VellumTheme.accent, lineWidth: 2)
        case .alreadyOpen:
            EmptyView()
        case .refused:
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    VellumTheme.muted,
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                )
        }
    }

    @ViewBuilder
    private var label: some View {
        switch intent {
        case .split:
            NoteGhostLabel(title: title, spaceColor: spaceColor)
        case .alreadyOpen:
            NoteGhostLabel(
                title: "Already open — jump here",
                spaceColor: spaceColor
            )
        case .refused:
            Text("No room to split")
                .font(.vellumNewsreader(15, weight: .semibold))
                .foregroundStyle(VellumTheme.muted)
        }
    }
}
