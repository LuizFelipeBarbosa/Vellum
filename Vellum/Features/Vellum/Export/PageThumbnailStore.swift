import Observation
import UIKit
import VellumCore

private struct PageThumbnailRenderRequest: @unchecked Sendable {
    let pageIndex: Int
    let content: NotePageRenderer.Content
    let pointSize: CGSize
    let scale: CGFloat
}

private struct PageThumbnailRenderResult: @unchecked Sendable {
    let image: UIImage
}

private actor PageThumbnailRenderer {
    func render(_ request: PageThumbnailRenderRequest) -> PageThumbnailRenderResult {
        PageThumbnailRenderResult(
            image: NotePageRenderer.image(
                pageIndex: request.pageIndex,
                content: request.content,
                pointSize: request.pointSize,
                scale: request.scale
            )
        )
    }
}

@MainActor
@Observable
final class PageThumbnailStore {
    private static let maximumImageCount = 60

    private(set) var images: [Int: UIImage] = [:]
    private(set) var generation = 0

    private var inFlight = Set<Int>()
    private var lastRequestSequenceByPageIndex: [Int: Int] = [:]
    private var requestSequence = 0
    private let renderer = PageThumbnailRenderer()

    /// Invalidates every thumbnail so visible rows re-render on their next request.
    func markDirty() {
        generation += 1
        images.removeAll()
        inFlight.removeAll()
        lastRequestSequenceByPageIndex.removeAll()
    }

    /// Renders one requested page after coalescing changes for 500 milliseconds.
    func requestImage(
        for pageIndex: Int,
        content: NotePageRenderer.Content
    ) async {
        guard (0..<content.pageCount).contains(pageIndex) else { return }

        touch(pageIndex)
        guard images[pageIndex] == nil, !inFlight.contains(pageIndex) else {
            return
        }

        inFlight.insert(pageIndex)
        let requestedGeneration = generation
        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            if requestedGeneration == generation {
                inFlight.remove(pageIndex)
            }
            return
        }
        guard !Task.isCancelled, requestedGeneration == generation else {
            return
        }

        let width: CGFloat = 156
        let pointSize = CGSize(
            width: width,
            height: width * CGFloat(content.geometry.aspectRatio)
        )
        let result = await renderer.render(
            PageThumbnailRenderRequest(
                pageIndex: pageIndex,
                content: content,
                pointSize: pointSize,
                scale: 2
            )
        )

        guard requestedGeneration == generation else { return }
        inFlight.remove(pageIndex)
        guard !Task.isCancelled else { return }

        images[pageIndex] = result.image
        touch(pageIndex)
        evictIfNeeded()
    }

    private func touch(_ pageIndex: Int) {
        requestSequence += 1
        lastRequestSequenceByPageIndex[pageIndex] = requestSequence
    }

    private func evictIfNeeded() {
        while images.count > Self.maximumImageCount {
            guard let leastRecentPageIndex = images.keys.min(by: { lhs, rhs in
                lastRequestSequenceByPageIndex[lhs, default: 0]
                    < lastRequestSequenceByPageIndex[rhs, default: 0]
            }) else {
                return
            }
            images[leastRecentPageIndex] = nil
            lastRequestSequenceByPageIndex[leastRecentPageIndex] = nil
        }
    }
}
