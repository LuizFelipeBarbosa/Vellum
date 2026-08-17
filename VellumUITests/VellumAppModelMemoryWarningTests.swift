import Foundation
import UIKit
@testable import Vellum
import XCTest

@MainActor
final class VellumAppModelMemoryWarningTests: XCTestCase {
    private var rootDirectory: URL!
    private var container: AppContainer!

    override func setUp() async throws {
        try await super.setUp()
        rootDirectory = try TemporaryDirectory.make()
        container = AppContainer.live(rootDirectory: rootDirectory)
    }

    override func tearDown() async throws {
        container = nil
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        rootDirectory = nil
        try await super.tearDown()
    }

    func testMemoryWarningClearsImageCachesForEveryOpenPane() async throws {
        let appModel = VellumAppModel(container: container, arguments: [])
        let firstPane = makePane()
        let secondPane = makePane()
        appModel.split.insertColumn(with: firstPane, at: nil)
        appModel.split.insertColumn(with: secondPane, at: nil)

        for (index, pane) in appModel.split.panes.enumerated() {
            let image = UIImage()
            pane.noteModel.canvasElements.cacheImage(
                image,
                data: Data([UInt8(index)]),
                forAssetPath: "assets/image-\(index).jpg"
            )
            pane.noteModel.pdfCache.insertImage(
                image,
                for: PdfPageImageCache.ImageKey(pageID: UUID(), bucket: .fit)
            )
            XCTAssertFalse(pane.noteModel.canvasElements.imageCache.isEmpty)
            XCTAssertFalse(pane.noteModel.pdfCache.images.isEmpty)
        }

        // Re-post inside the poll: NotificationCenter is push-only, so a single post
        // that races the app model's subscription attach would be missed permanently.
        let didClearCaches = try await waitUntil {
            NotificationCenter.default.post(
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )
            return appModel.split.panes.allSatisfy {
                $0.noteModel.canvasElements.imageCache.isEmpty
                    && $0.noteModel.pdfCache.images.isEmpty
            }
        }
        XCTAssertTrue(didClearCaches)
    }

    private func makePane() -> NotePane {
        NotePane(
            noteModel: NoteScreenModel(
                noteID: UUID(),
                container: container,
                onNoteChanged: { _ in }
            )
        )
    }

    private func waitUntil(
        _ condition: () -> Bool
    ) async throws -> Bool {
        for _ in 0..<100 {
            if condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
