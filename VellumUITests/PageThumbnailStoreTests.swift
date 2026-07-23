import PencilKit
@testable import Vellum
import XCTest

@MainActor
final class PageThumbnailStoreTests: XCTestCase {
    func testMarkDirtyBumpsGenerationAndClearsRenderedImages() async {
        let store = PageThumbnailStore()
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [],
            imagesByAssetPath: [:],
            pageCount: 1
        )

        await store.requestImage(for: 0, content: content)

        XCTAssertNotNil(store.images[0])
        let renderedGeneration = store.generation

        store.markDirty()

        XCTAssertEqual(store.generation, renderedGeneration + 1)
        XCTAssertTrue(store.images.isEmpty)
    }
}
