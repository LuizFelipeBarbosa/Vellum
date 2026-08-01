import SwiftUI
import VellumCore

/// The page-thumbnail panel, over a tap-to-dismiss scrim.
struct NoteThumbnailOverlay: View {
    let model: NoteScreenModel
    let store: PageThumbnailStore
    let pageState: NotePageState
    let contentProvider: () -> NotePageRenderer.Content
    let onScrollToPage: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            ThumbnailPanelView(
                store: store,
                pages: model.note?.pages ?? [],
                pageCount: pageState.pageCount,
                currentPageIndex: pageState.currentPageIndex,
                geometry: model.note?.pageGeometry ?? .a4,
                contentProvider: contentProvider,
                onSelect: { index in
                    onScrollToPage(index)
                    onDismiss()
                },
                onMovePages: { source, destination in
                    // Remap only after the model confirms the mutation: a
                    // rejected move must leave the cache untouched or rows
                    // would show the wrong pages' thumbnails indefinitely.
                    let pageCount = pageState.pageCount
                    guard model.movePages(source: source, to: destination) else {
                        return
                    }
                    store.applyMove(
                        fromOffsets: source,
                        toOffset: destination,
                        pageCount: pageCount
                    )
                },
                onDeletePage: { index in
                    let pageCount = pageState.pageCount
                    guard model.deletePage(at: index) else { return }
                    store.applyDeletion(at: index, pageCount: pageCount)
                },
                onAddPage: {
                    model.addPageAtEnd()
                },
                onDismiss: onDismiss
            )
            .frame(width: 250)
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
