import Observation
import SwiftUI
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
    private var imageGeneration: [Int: Int] = [:]
    private var lastRequestSequenceByPageIndex: [Int: Int] = [:]
    private var requestSequence = 0
    private var remapVersion = 0
    private let renderer = PageThumbnailRenderer()

    // UI tests pass this argument to hold the loading placeholder on screen
    // long enough to assert against; production keeps the 500ms coalescing.
    private let debounceMilliseconds =
        ProcessInfo.processInfo.arguments.contains("-thumbnail-slow-render")
            ? 3000
            : 500

    /// Marks thumbnails stale while keeping existing images visible instead of
    /// blanking to a spinner while rows re-render in the background.
    func markDirty() {
        generation += 1
        inFlight.removeAll()
    }

    /// Renders one requested page after coalescing changes for 500 milliseconds.
    func requestImage(
        for pageIndex: Int,
        content: NotePageRenderer.Content
    ) async {
        guard (0..<content.pageCount).contains(pageIndex) else { return }

        touch(pageIndex)
        guard (images[pageIndex] == nil || imageGeneration[pageIndex] != generation),
              !inFlight.contains(pageIndex) else {
            return
        }

        inFlight.insert(pageIndex)
        let requestedGeneration = generation
        let requestedRemapVersion = remapVersion
        do {
            try await Task.sleep(for: .milliseconds(debounceMilliseconds))
        } catch {
            if requestedGeneration == generation {
                inFlight.remove(pageIndex)
            }
            return
        }
        guard !Task.isCancelled,
              requestedGeneration == generation,
              requestedRemapVersion == remapVersion else {
            return
        }

        let pointSize = CGSize(
            width: ThumbnailLayout.width,
            height: ThumbnailLayout.width * CGFloat(content.geometry.aspectRatio)
        )
        let result = await renderer.render(
            PageThumbnailRenderRequest(
                pageIndex: pageIndex,
                content: content,
                pointSize: pointSize,
                scale: 2
            )
        )

        guard requestedGeneration == generation,
              requestedRemapVersion == remapVersion else {
            return
        }
        inFlight.remove(pageIndex)
        guard !Task.isCancelled else { return }

        images[pageIndex] = result.image
        imageGeneration[pageIndex] = requestedGeneration
        touch(pageIndex)
        evictIfNeeded()
    }

    /// Moves cached thumbnails with their pages so a reorder never blanks rows.
    func applyMove(fromOffsets source: IndexSet, toOffset destination: Int, pageCount: Int) {
        var order = Array(0..<pageCount)
        order.move(fromOffsets: source, toOffset: destination)

        var remappedImages: [Int: UIImage] = [:]
        var remappedImageGeneration: [Int: Int] = [:]
        var remappedRequestSequence: [Int: Int] = [:]
        for (newIndex, oldIndex) in order.enumerated() {
            if let image = images[oldIndex] {
                remappedImages[newIndex] = image
            }
            if let generation = imageGeneration[oldIndex] {
                remappedImageGeneration[newIndex] = generation
            }
            if let sequence = lastRequestSequenceByPageIndex[oldIndex] {
                remappedRequestSequence[newIndex] = sequence
            }
        }

        images = remappedImages
        imageGeneration = remappedImageGeneration
        lastRequestSequenceByPageIndex = remappedRequestSequence
        remapVersion += 1
        inFlight.removeAll()
    }

    /// Shifts cached thumbnails down after a deletion so a delete never blanks rows.
    func applyDeletion(at index: Int, pageCount: Int) {
        var order = Array(0..<pageCount)
        order.remove(at: index)

        var remappedImages: [Int: UIImage] = [:]
        var remappedImageGeneration: [Int: Int] = [:]
        var remappedRequestSequence: [Int: Int] = [:]
        for (newIndex, oldIndex) in order.enumerated() {
            if let image = images[oldIndex] {
                remappedImages[newIndex] = image
            }
            if let generation = imageGeneration[oldIndex] {
                remappedImageGeneration[newIndex] = generation
            }
            if let sequence = lastRequestSequenceByPageIndex[oldIndex] {
                remappedRequestSequence[newIndex] = sequence
            }
        }

        images = remappedImages
        imageGeneration = remappedImageGeneration
        lastRequestSequenceByPageIndex = remappedRequestSequence
        remapVersion += 1
        inFlight.removeAll()
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
            imageGeneration[leastRecentPageIndex] = nil
            lastRequestSequenceByPageIndex[leastRecentPageIndex] = nil
        }
    }
}
