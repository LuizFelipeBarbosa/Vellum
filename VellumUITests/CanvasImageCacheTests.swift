import Foundation
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class CanvasImageCacheTests: XCTestCase {
    func testCacheMissRequestsReloadAndRepopulatedEntryCanBeRead() throws {
        let store = CanvasElementsStore()
        let data = try XCTUnwrap(makePNGData())
        let image = try XCTUnwrap(UIImage(data: data))
        let oldestAssetPath = "assets/image-0.png"

        for index in 0..<61 {
            store.cacheImage(
                image,
                data: data,
                forAssetPath: "assets/image-\(index).png"
            )
        }

        var missedAssetPath: String?
        store.onImageCacheMiss = { missedAssetPath = $0 }

        XCTAssertNil(store.cachedImage(for: oldestAssetPath))
        XCTAssertEqual(missedAssetPath, oldestAssetPath)

        store.cacheImage(image, data: data, forAssetPath: oldestAssetPath)

        XCTAssertNotNil(store.cachedImage(for: oldestAssetPath))
    }

    func testCacheReadMakesEntryMoreRecentBeforeEviction() throws {
        let store = CanvasElementsStore()
        let data = try XCTUnwrap(makePNGData())
        let image = try XCTUnwrap(UIImage(data: data))
        let oldestAssetPath = "assets/image-0.png"
        let secondOldestAssetPath = "assets/image-1.png"

        for index in 0..<60 {
            store.cacheImage(
                image,
                data: data,
                forAssetPath: "assets/image-\(index).png"
            )
        }

        XCTAssertNotNil(store.cachedImage(for: oldestAssetPath))
        store.cacheImage(image, data: data, forAssetPath: "assets/image-60.png")

        XCTAssertNotNil(store.cachedImage(for: oldestAssetPath))
        XCTAssertNil(store.cachedImage(for: secondOldestAssetPath))
    }

    func testExportLoadsEveryReferencedImageBeyondCacheBound() async throws {
        let rootDirectory = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let (container, note, model) = try await NoteScreenModelFixture.make(
            rootDirectory: rootDirectory,
            title: "Lossless image export"
        )
        let data = try XCTUnwrap(makePNGData())
        let assetPaths = (0..<70).map { "assets/export-image-\($0).png" }
        let elements = assetPaths.enumerated().map { index, assetPath in
            CanvasElement(
                content: .image(
                    ImageContent(
                        assetPath: assetPath,
                        originalPixelSize: CanvasSize(width: 1, height: 1)
                    )
                ),
                frame: CanvasRect(x: Double(index), y: 0, width: 1, height: 1)
            )
        }

        var persistedNote = note
        persistedNote.pages[0].elements = elements
        try await container.notes.saveNote(persistedNote)
        for assetPath in assetPaths {
            try await container.notes.saveAsset(
                data,
                noteID: note.id,
                relativePath: assetPath
            )
        }
        await model.load()

        let cachedImageCount = assetPaths.reduce(into: 0) { count, assetPath in
            if model.canvasElements.cachedImage(for: assetPath) != nil {
                count += 1
            }
        }
        XCTAssertEqual(cachedImageCount, 60)

        let images = try await model.loadImagesForExport()

        XCTAssertEqual(images.count, 70)
        for assetPath in assetPaths {
            XCTAssertNotNil(images[assetPath], "Missing exported image at \(assetPath)")
        }
    }

    func testCopyReportsFailureWhenSelectedImageDataWasEvicted() async throws {
        let assetPath = "assets/selected.png"
        let element = CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: assetPath,
                    originalPixelSize: CanvasSize(width: 1, height: 1)
                )
            ),
            frame: CanvasRect(x: 10, y: 10, width: 20, height: 20)
        )
        let harness = CanvasHarness.make(strokes: [], elements: [element])
        let data = try XCTUnwrap(makePNGData())
        let image = try XCTUnwrap(UIImage(data: data))
        harness.store.cacheImage(image, data: data, forAssetPath: assetPath)
        for index in 0..<60 {
            harness.store.cacheImage(
                image,
                data: data,
                forAssetPath: "assets/other-image-\(index).png"
            )
        }
        harness.controller.beginCapture(at: .zero, mode: .boxed)
        harness.controller.extendCapture(to: CGPoint(x: 40, y: 40))
        harness.controller.endCapture()
        var failureMessage: String?
        harness.controller.onOperationFailed = { failureMessage = $0 }

        let copied = await harness.controller.copySelection()
        XCTAssertFalse(copied)
        XCTAssertFalse(failureMessage?.isEmpty ?? true)
    }

    private func makePNGData() -> Data? {
        Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nH0AAAAASUVORK5CYII="
        )
    }
}
