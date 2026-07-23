import SwiftUI
import VellumCore

private struct ThumbnailRequestID: Hashable {
    let pageIndex: Int
    let generation: Int
}

struct ThumbnailPanelView: View {
    @Environment(\.colorScheme) private var colorScheme

    let store: PageThumbnailStore
    let pages: [NotePage]
    let pageCount: Int
    let currentPageIndex: Int
    let geometry: PageGeometry
    let contentProvider: () -> NotePageRenderer.Content
    let onSelect: (Int) -> Void
    let onMovePages: (IndexSet, Int) -> Void
    let onAddPage: () -> Void
    let onDismiss: () -> Void

    private let thumbnailWidth: CGFloat = 156

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pages")
                    .font(.vellumNewsreader(22, weight: .semibold))

                Spacer()

                Button("×") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 18))
                .foregroundStyle(VellumTheme.mutedCount)
                .accessibilityLabel("Close pages")
            }

            ScrollViewReader { proxy in
                List {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, _ in
                        thumbnailCell(pageIndex: index)
                            .id(index)
                            .padding(.bottom, 16)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                    .onMove { source, destination in
                        onMovePages(source, min(destination, pages.count))
                    }

                    if pageCount > pages.count {
                        thumbnailCell(pageIndex: pages.count)
                            .id(pages.count)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
                .scrollIndicators(.hidden)
                .onAppear {
                    withAnimation {
                        proxy.scrollTo(currentPageIndex, anchor: .center)
                    }
                }
            }

            Button {
                onAddPage()
            } label: {
                Label("Add page", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VellumTheme.accentDark)
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
    }

    private func thumbnailCell(pageIndex: Int) -> some View {
        Button {
            onSelect(pageIndex)
        } label: {
            VStack(spacing: 7) {
                Group {
                    if let image = store.images[pageIndex] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(VellumTheme.paper)
                            ProgressView()
                        }
                    }
                }
                .frame(
                    width: thumbnailWidth,
                    height: thumbnailWidth * CGFloat(geometry.aspectRatio)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    if pageIndex == currentPageIndex {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(VellumTheme.accent, lineWidth: 2)
                    }
                }

                Text("\(pageIndex + 1)")
                    .font(.vellumMono(10.5))
                    .foregroundStyle(
                        pageIndex == currentPageIndex
                            ? VellumTheme.accentDark
                            : VellumTheme.mutedCount
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .task(
            id: ThumbnailRequestID(
                pageIndex: pageIndex,
                generation: store.generation
            )
        ) {
            var content = contentProvider()
            content.interfaceStyle = colorScheme == .dark ? .dark : .light
            await store.requestImage(for: pageIndex, content: content)
        }
    }
}
