import SwiftUI
import VellumCore

struct SplitDragLift: Equatable {
    let dragID: UUID
    let noteID: UUID
    let title: String
    let spaceColor: Color?
    var grabOffset: CGSize
}

enum SidebarDropResolution: Equatable {
    case cancelZone
    case capacityFull
    case target(SplitGridDropTarget)
}

struct NoteGhostLabel: View {
    let title: String
    let spaceColor: Color?

    var body: some View {
        HStack(spacing: 8) {
            if let spaceColor {
                Circle()
                    .fill(spaceColor)
                    .frame(width: 7, height: 7)
            }

            Text(title)
                .font(.vellumNewsreader(15, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
    }
}

struct NoteDragPreviewCard: View {
    let title: String
    let spaceColor: Color?
    var expandedSize: CGSize? = nil

    var body: some View {
        NoteGhostLabel(title: title, spaceColor: spaceColor)
        .padding(14)
        .frame(
            width: expandedSize?.width ?? 180,
            height: expandedSize?.height,
            alignment: .topLeading
        )
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.18), radius: 18, x: -4, y: 12)
        .scaleEffect(expandedSize == nil ? 1.03 : 1)
        .allowsHitTesting(false)
    }
}
