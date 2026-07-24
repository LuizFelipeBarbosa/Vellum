import PencilKit
@testable import Vellum
import XCTest

@MainActor
final class PageThumbnailStoreTests: XCTestCase {
    func testMarkDirtyKeepsExistingImageButBumpsGeneration() async {
        let store = PageThumbnailStore()
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [],
            imagesByAssetPath: [:],
            pageCount: 1
        )

        await store.requestImage(for: 0, content: content)

        let renderedImage = store.images[0]
        XCTAssertNotNil(renderedImage)
        let renderedGeneration = store.generation

        store.markDirty()

        XCTAssertEqual(store.generation, renderedGeneration + 1)
        XCTAssertTrue(store.images[0] === renderedImage)
        XCTAssertFalse(store.images.isEmpty)
    }

    func testApplyMoveRemapsCachedImageToNewIndex() async {
        let store = PageThumbnailStore()
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [],
            imagesByAssetPath: [:],
            pageCount: 3
        )

        await store.requestImage(for: 0, content: content)

        let renderedImage = store.images[0]
        XCTAssertNotNil(renderedImage)

        store.applyMove(fromOffsets: [0], toOffset: 2, pageCount: 3)

        XCTAssertTrue(store.images[1] === renderedImage)
        XCTAssertNil(store.images[0])
    }

    func testApplyDeletionShiftsCachedImagesDown() async {
        let store = PageThumbnailStore()
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [],
            imagesByAssetPath: [:],
            pageCount: 3
        )

        await store.requestImage(for: 1, content: content)

        let renderedImage = store.images[1]
        XCTAssertNotNil(renderedImage)

        store.applyDeletion(at: 0, pageCount: 3)

        XCTAssertTrue(store.images[0] === renderedImage)
        XCTAssertNil(store.images[2])
    }

    func testRequestImageReRendersStaleEntryAfterMarkDirty() async {
        let store = PageThumbnailStore()
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [],
            imagesByAssetPath: [:],
            pageCount: 1
        )

        await store.requestImage(for: 0, content: content)

        let firstRenderedImage = store.images[0]
        XCTAssertNotNil(firstRenderedImage)

        store.markDirty()
        await store.requestImage(for: 0, content: content)

        let secondRenderedImage = store.images[0]
        XCTAssertNotNil(secondRenderedImage)
        XCTAssertFalse(secondRenderedImage === firstRenderedImage)
        XCTAssertEqual(store.images.count, 1)
    }
}
