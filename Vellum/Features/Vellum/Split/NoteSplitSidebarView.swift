import Foundation
import SwiftUI
import VellumCore

@MainActor
struct NoteSplitSidebarView: View {
    @Bindable var app: VellumAppModel
    let containerWidth: CGFloat
    let onDismiss: () -> Void
    let onDragPrepare: () -> Void
    let onDragBegan: (NoteSummary, Color?, CGPoint) -> Void
    let onDragMoved: (CGPoint) -> Void
    let onDragEnded: () -> Void
    let onDragCancelled: () -> Void

    var body: some View {
        let summaries = app.library.summaries

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes")
                        .font(.vellumNewsreader(22, weight: .semibold))

                    Text(summaries.count == 1 ? "1 note" : "\(summaries.count) notes")
                        .font(.vellumMono(10.5))
                        .foregroundStyle(VellumTheme.mutedCount)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VellumTheme.mutedControl)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close notes")
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(summaries) { summary in
                        noteRow(summary)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .gesture(
                SplitSidebarRowDragGesture(
                    noteIDs: summaries.map(\.id),
                    onPrepare: onDragPrepare,
                    onBegin: { noteID, location in
                        guard let summary = app.library.summaries.first(
                            where: { $0.id == noteID }
                        ) else {
                            onDragCancelled()
                            return
                        }
                        onDragBegan(summary, spaceColor(for: summary), location)
                    },
                    onMove: onDragMoved,
                    onEnd: onDragEnded,
                    onCancel: onDragCancelled
                )
            )
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.18), radius: 18, x: -4, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vellum-note-sidebar")
        .task {
            await app.library.refresh()
        }
    }

    private func noteRow(_ summary: NoteSummary) -> some View {
        let openPane = app.split.pane(for: summary.id)
        let title = displayTitle(for: summary)

        return Button {
            Task {
                if let openPane = app.split.pane(for: summary.id) {
                    app.split.focus(openPane.id)
                    return                        // sidebar stays open
                }
                await app.openNote(summary.id)    // default .replaceFocused placement
                onDismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if let color = spaceColor(for: summary) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: openPane == nil ? .regular : .semibold))
                        .foregroundStyle(VellumTheme.ink)
                        .lineLimit(1)

                    Text(summary.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.vellumMono(10.5))
                        .foregroundStyle(VellumTheme.mutedCount)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: SplitSidebarLayout.rowHeight)
            .background(
                openPane == nil ? .clear : VellumTheme.accent(0.1),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func spaceColor(for summary: NoteSummary) -> Color? {
        guard let spaceID = summary.spaceID,
              let space = app.library.spaces.first(
                where: { $0.space.id == spaceID }
              )?.space else {
            return nil
        }
        return VellumTheme.color(for: space.color)
    }

    private func displayTitle(for summary: NoteSummary) -> String {
        summary.title.isEmpty ? "Untitled" : summary.title
    }
}
