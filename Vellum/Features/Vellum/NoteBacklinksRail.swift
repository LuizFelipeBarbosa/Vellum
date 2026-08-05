import SwiftUI
import VellumCore

/// Tabs down the trailing edge of the canvas, one per note that links here.
struct NoteBacklinksRail: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let backlinks: [Backlink]
    let onOpen: (UUID) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(backlinks, id: \.sourceNoteID) { backlink in
                let shape = VellumOrganicRectangle(
                    topLeading: 10,
                    bottomLeading: 10,
                    bottomTrailing: 0,
                    topTrailing: 0,
                    straightRadius: 10,
                    isOrganic: vellumWobble
                )

                Button {
                    onOpen(backlink.sourceNoteID)
                } label: {
                    HStack(spacing: 4) {
                        Text(backlink.sourceTitle)
                            .foregroundStyle(VellumTheme.bodyMuted)
                            .lineLimit(1)
                        Text("· \(backlink.kind.rawValue)")
                            .foregroundStyle(VellumTheme.mutedCount)
                    }
                    .font(.system(size: 12.5))
                    .padding(.leading, 16)
                    .padding(.trailing, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        VellumTheme.card,
                        in: shape
                    )
                    .overlay {
                        shape.stroke(VellumTheme.ink(0.14), lineWidth: 1)
                    }
                    .shadow(color: VellumTheme.ink(0.06), radius: 3, x: -2, y: 2)
                }
                .buttonStyle(.plain)
            }

            Text("\(backlinks.count) \(backlinks.count == 1 ? "backlink" : "backlinks")")
                .font(.vellumMono(10.5))
                .foregroundStyle(VellumTheme.mutedCount)
                .padding(.trailing, 14)
        }
    }
}
