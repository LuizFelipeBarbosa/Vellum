import SwiftUI
import VellumCore

struct ThumbnailPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingDeleteIndex: Int?

    let store: PageThumbnailStore
    let pages: [NotePage]
    let pageCount: Int
    let currentPageIndex: Int
    let geometry: PageGeometry
    let contentProvider: () -> NotePageRenderer.Content
    let onSelect: (Int) -> Void
    let onMovePages: (IndexSet, Int) -> Void
    let onDeletePage: (Int) -> Void
    let onAddPage: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pages")
                        .font(.vellumNewsreader(22, weight: .semibold))

                    Text(pageCount == 1 ? "1 page" : "\(pageCount) pages")
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
                .accessibilityLabel("Close pages")
            }

            ReorderableThumbnailList(
                store: store,
                pages: pages,
                pageCount: pageCount,
                currentPageIndex: currentPageIndex,
                geometry: geometry,
                contentProvider: contentProvider,
                onSelect: onSelect,
                onMovePages: onMovePages,
                onDeletePage: { pendingDeleteIndex = $0 }
            )

            Button {
                onAddPage()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add page")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VellumTheme.accentDark)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            VellumTheme.ink(0.2),
                            style: StrokeStyle(
                                lineWidth: 1,
                                dash: [4, 3]
                            )
                        )
                }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.18), radius: 18, x: -4, y: 12)
        .onChange(of: colorScheme) { _, _ in
            store.markDirty()
        }
        .confirmationDialog(
            "Delete page \((pendingDeleteIndex ?? 0) + 1)?",
            isPresented: Binding(
                get: { pendingDeleteIndex != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteIndex = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDeleteIndex {
                Button("Delete", role: .destructive) {
                    onDeletePage(pendingDeleteIndex)
                    self.pendingDeleteIndex = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteIndex = nil
            }
        }
    }
}
