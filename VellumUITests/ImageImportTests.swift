import Foundation
import ImageIO
@testable import Vellum
import VellumCore
import UniformTypeIdentifiers
import XCTest

@MainActor
final class ImageImportTests: XCTestCase {
    func testProcessForStorageDownscalesLargeImage() async throws {
        let data = renderedImageData(width: 4000, height: 3000)

        let processed = try await ImageImportPipeline.processForStorage(data)

        XCTAssertEqual(max(processed.pixelSize.width, processed.pixelSize.height), 2048)
        XCTAssertEqual(processed.pixelSize.width, 2048, accuracy: 2)
        XCTAssertEqual(processed.pixelSize.height, 1536, accuracy: 2)
        XCTAssertNotNil(UIImage(data: processed.jpegData))
    }

    func testProcessForStorageDoesNotUpscaleSmallImage() async throws {
        let data = renderedImageData(width: 500, height: 400)

        let processed = try await ImageImportPipeline.processForStorage(data)

        XCTAssertLessThanOrEqual(
            max(processed.pixelSize.width, processed.pixelSize.height),
            500
        )
        XCTAssertNotNil(UIImage(data: processed.jpegData))
    }

    func testProcessForStorageRejectsNonImageData() async {
        let data = Data((0..<64).map(UInt8.init))

        do {
            _ = try await ImageImportPipeline.processForStorage(data)
            XCTFail("Expected non-image data to throw")
        } catch ImageImportPipeline.ImageImportError.undecodable {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcessForStorageBakesInNonUpExifOrientation() async throws {
        let data = jpegDataWithExifOrientation(width: 400, height: 300, orientation: 6)

        let processed = try await ImageImportPipeline.processForStorage(data)

        XCTAssertEqual(processed.pixelSize.width, 300, accuracy: 2)
        XCTAssertEqual(processed.pixelSize.height, 400, accuracy: 2)
        let resultImage = try XCTUnwrap(UIImage(data: processed.jpegData))
        XCTAssertEqual(resultImage.imageOrientation, .up)
    }

    func testImageImportRoundTripsAssetElementAndCache() async throws {
        let rootDirectory = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let (note, model) = try await makeLoadedModel(
            rootDirectory: rootDirectory,
            title: "Image round trip"
        )
        let visibleRect = CGRect(x: 0, y: 0, width: 1000, height: 1400)

        await model.importImage(
            renderedImageData(width: 1600, height: 1200),
            visibleContentRect: visibleRect
        )

        let importedElement = try XCTUnwrap(model.canvasElements.elements.first)
        XCTAssertEqual(model.canvasElements.elements.count, 1)
        guard case .image(let importedContent) = importedElement.content else {
            XCTFail("Expected an image element")
            return
        }
        XCTAssertEqual(max(importedElement.frame.width, importedElement.frame.height), 600, accuracy: 2)
        // The clamp pushes the image left off the viewport's center so it fits the page.
        XCTAssertEqual(
            importedElement.frame.x,
            Double(PageLayout.contentWidth) - importedElement.frame.width,
            accuracy: 2
        )
        XCTAssertEqual(
            importedElement.frame.y + importedElement.frame.height / 2,
            visibleRect.midY,
            accuracy: 2
        )

        await model.flushPendingSave()

        let freshRepository = FileNoteRepository(rootDirectory: rootDirectory)
        let reloadedNote = try await freshRepository.loadNote(id: note.id)
        let reloadedElements = try XCTUnwrap(reloadedNote.pages.first?.elements)
        let reloadedElement = try XCTUnwrap(reloadedElements.first)
        XCTAssertEqual(reloadedElements.count, 1)
        guard case .image(let reloadedContent) = reloadedElement.content else {
            XCTFail("Expected a reloaded image element")
            return
        }
        XCTAssertEqual(reloadedContent.assetPath, importedContent.assetPath)

        let reloadedAsset = try await freshRepository.loadAsset(
            noteID: note.id,
            relativePath: reloadedContent.assetPath
        )
        let assetData = try XCTUnwrap(reloadedAsset)
        XCTAssertNotNil(UIImage(data: assetData))

        let freshContainer = AppContainer.live(rootDirectory: rootDirectory)
        let freshModel = NoteScreenModel(
            noteID: note.id,
            container: freshContainer,
            onNoteChanged: { _ in }
        )
        await freshModel.load()

        XCTAssertNotNil(freshModel.canvasElements.imageCache[reloadedContent.assetPath])
    }

    func testImageImportClampsWidthToPageWidthForWideImage() async throws {
        let rootDirectory = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let (_, model) = try await makeLoadedModel(
            rootDirectory: rootDirectory,
            title: "Wide image import"
        )
        let importedID = await model.importImage(
            renderedImageData(width: 4000, height: 1000),
            visibleContentRect: CGRect(x: 0, y: 0, width: 2000, height: 2000)
        )

        let importedElement = try XCTUnwrap(model.canvasElements.elements.first)
        XCTAssertNotNil(importedID)
        XCTAssertEqual(importedID, importedElement.id)
        XCTAssertEqual(importedElement.frame.width, Double(PageLayout.contentWidth), accuracy: 2)
        XCTAssertEqual(
            importedElement.frame.height / importedElement.frame.width,
            1000.0 / 4000.0,
            accuracy: 0.01
        )
        XCTAssertEqual(importedElement.frame.x, 0, accuracy: 2)
    }

    func testUndoRemovesImportedImageElement() async throws {
        let rootDirectory = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let (_, model) = try await makeLoadedModel(
            rootDirectory: rootDirectory,
            title: "Undo image import"
        )
        let undoManager = UndoManager()
        model.canvasElements.undoManagerOverride = undoManager

        await model.importImage(
            renderedImageData(width: 800, height: 600),
            visibleContentRect: CGRect(x: 0, y: 0, width: 800, height: 1000)
        )

        XCTAssertEqual(model.canvasElements.elements.count, 1)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertTrue(model.canvasElements.elements.isEmpty)
        await model.flushPendingSave()
    }

    private func renderedImageData(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.pngData()!
    }

    private func jpegDataWithExifOrientation(
        width: Int,
        height: Int,
        orientation: Int
    ) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let cgImage = image.cgImage else {
            XCTFail("Failed to create CGImage")
            return Data()
        }
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            XCTFail("Failed to create CGImageDestination")
            return Data()
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            XCTFail("Failed to finalize image destination")
            return Data()
        }
        return mutableData as Data
    }

    private func makeRootDirectory() throws -> URL {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        return rootDirectory
    }

    private func makeLoadedModel(
        rootDirectory: URL,
        title: String
    ) async throws -> (Note, NoteScreenModel) {
        let container = AppContainer.live(rootDirectory: rootDirectory)
        let note = try await container.notes.createNote(title: title)
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()
        return (note, model)
    }
}
