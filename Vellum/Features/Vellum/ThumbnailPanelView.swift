import SwiftUI
import VellumCore

struct ThumbnailPanelView: View {
    let store: PageThumbnailStore
    let pageCount: Int
    let currentPageIndex: Int
    let onSelect: (Int) -> Void
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
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            thumbnailCell(pageIndex: index)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    withAnimation {
                        proxy.scrollTo(currentPageIndex, anchor: .center)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.18), radius: 18, x: -4, y: 12)
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
                    height: thumbnailWidth * PageLayout.a4AspectRatio
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
        }
        .buttonStyle(.plain)
    }
}
