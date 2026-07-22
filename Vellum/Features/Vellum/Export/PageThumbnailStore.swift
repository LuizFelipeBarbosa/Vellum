import Observation
import UIKit
import VellumCore

@MainActor
@Observable
final class PageThumbnailStore {
    private(set) var images: [Int: UIImage] = [:]

    private var isDirty = true
    private var generation = 0

    /// Marks the cached thumbnails for regeneration.
    func markDirty() {
        isDirty = true
        generation += 1
    }

    /// Regenerates every page after coalescing changes for 500 milliseconds.
    func regenerate(content: NotePageRenderer.Content) async {
        guard isDirty else { return }

        generation += 1
        let requestedGeneration = generation
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, requestedGeneration == generation else { return }

        let width: CGFloat = 156
        let pointSize = CGSize(
            width: width,
            height: width * PageLayout.pageHeight / PageLayout.contentWidth
        )
        var renderedImages: [Int: UIImage] = [:]
        for pageIndex in 0..<max(0, content.pageCount) {
            renderedImages[pageIndex] = NotePageRenderer.image(
                pageIndex: pageIndex,
                content: content,
                pointSize: pointSize,
                scale: 2
            )
        }

        guard requestedGeneration == generation else { return }
        images = renderedImages
        isDirty = false
    }
}
