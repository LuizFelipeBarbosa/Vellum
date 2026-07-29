import Foundation
import PencilKit
import UIKit
import XCTest

@MainActor
final class PhotoInteractionFlowUITests: XCTestCase {
    private static let topLeftHandleLabel = "Resize handle, top left corner"
    private static let bottomRightHandleLabel = "Resize handle, bottom right corner"
    private static let emptyCanvasPoint = CGVector(dx: 0.85, dy: 0.85)

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSelectToolTapSelectsPhotoAndEmptyCanvasTapDeselectsIt() throws {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")

        let photoCenter = try seedPhoto(in: app, window: window)

        window.coordinate(withNormalizedOffset: Self.emptyCanvasPoint).tap()
        assertResizeHandlesDisappear(in: app)

        window.coordinate(withNormalizedOffset: photoCenter).tap()
        assertResizeHandlesAppear(in: app)
    }

    func testInkToolTapBorrowsSelectForPhotoAndEmptyCanvasTapRestoresPen() throws {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        let photoCenter = try seedPhoto(in: app, window: window)

        app.terminate()
        app.launchArguments = ["-vellum-force-pencil-only"]
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let relaunchedWindow = app.windows.firstMatch
        XCTAssertTrue(
            relaunchedWindow.waitForExistence(timeout: 5),
            "app window not found after pencil-only relaunch"
        )
        ShapeFlowTestHelpers.selectTool("Pen", in: app)

        relaunchedWindow.coordinate(withNormalizedOffset: photoCenter).tap()
        assertResizeHandlesAppear(in: app, timeout: 10)
        XCTAssertTrue(
            app.buttons["Select"].isSelected,
            "tapping a photo from the Pen tool did not borrow the Select tool"
        )

        relaunchedWindow.coordinate(withNormalizedOffset: Self.emptyCanvasPoint).tap()
        assertResizeHandlesDisappear(in: app)

        let penRestored = expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: app.buttons["Pen"]
        )
        wait(for: [penRestored], timeout: 5)
    }

    private func seedPhoto(
        in app: XCUIApplication,
        window: XCUIElement
    ) throws -> CGVector {
        try writePhotoPayloadToPasteboard()

        ShapeFlowTestHelpers.selectTool("Pen", in: app)
        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.30, dy: 0.62)
        ).press(
            forDuration: 0.05,
            thenDragTo: window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.40, dy: 0.62)
            )
        )

        ShapeFlowTestHelpers.boxSelect(
            in: app,
            window: window,
            around: CGRect(
                x: window.frame.width * 0.26,
                y: window.frame.height * 0.56,
                width: window.frame.width * 0.20,
                height: window.frame.height * 0.12
            )
        )

        let pasteSelection = app.buttons["Paste selection"]
        XCTAssertTrue(
            pasteSelection.waitForExistence(timeout: 5),
            "Paste selection did not appear after selecting the scratch stroke"
        )
        XCTAssertTrue(
            pasteSelection.isEnabled,
            "Paste selection was disabled despite the seeded Vellum payload"
        )
        pasteSelection.tap()

        // The cross-app-paste permission alert is owned by SpringBoard, not Vellum.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowPaste = springboard.buttons["Allow Paste"]
        if allowPaste.waitForExistence(timeout: 5) {
            allowPaste.tap()
        }

        let handles = assertResizeHandlesAppear(in: app, timeout: 10)
        let center = CGPoint(
            x: (handles.topLeft.frame.midX + handles.bottomRight.frame.midX) / 2,
            y: (handles.topLeft.frame.midY + handles.bottomRight.frame.midY) / 2
        )
        let windowFrame = window.frame
        let normalizedCenter = CGVector(
            dx: (center.x - windowFrame.minX) / windowFrame.width,
            dy: (center.y - windowFrame.minY) / windowFrame.height
        )
        XCTAssertTrue(
            (0...1).contains(normalizedCenter.dx)
                && (0...1).contains(normalizedCenter.dy),
            "the pasted photo center was outside the visible app window"
        )
        return normalizedCenter
    }

    @discardableResult
    private func assertResizeHandlesAppear(
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> (topLeft: XCUIElement, bottomRight: XCUIElement) {
        let topLeft = resizeHandle(label: Self.topLeftHandleLabel, in: app)
        let bottomRight = resizeHandle(label: Self.bottomRightHandleLabel, in: app)
        XCTAssertTrue(
            topLeft.waitForExistence(timeout: timeout),
            "the photo's top-left resize handle did not appear"
        )
        XCTAssertTrue(
            bottomRight.waitForExistence(timeout: timeout),
            "the photo's bottom-right resize handle did not appear"
        )
        return (topLeft, bottomRight)
    }

    private func assertResizeHandlesDisappear(in app: XCUIApplication) {
        let topLeft = resizeHandle(label: Self.topLeftHandleLabel, in: app)
        let bottomRight = resizeHandle(label: Self.bottomRightHandleLabel, in: app)
        XCTAssertTrue(
            topLeft.waitForNonExistence(timeout: 5),
            "the photo's top-left resize handle remained after tapping empty canvas"
        )
        XCTAssertTrue(
            bottomRight.waitForNonExistence(timeout: 5),
            "the photo's bottom-right resize handle remained after tapping empty canvas"
        )
    }

    private func resizeHandle(label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    private func writePhotoPayloadToPasteboard() throws {
        let assetPath = "ui-test-photo-\(UUID().uuidString).png"
        let imageData = try renderedPhotoData()
        let payload = PasteboardPayload(
            drawingData: PKDrawing().dataRepresentation(),
            elements: [
                CanvasElementPayload(
                    id: UUID(),
                    kind: "image",
                    image: ImageContentPayload(
                        assetPath: assetPath,
                        originalPixelSize: CanvasSizePayload(width: 400, height: 300)
                    ),
                    frame: CanvasRectPayload(x: 250, y: 350, width: 220, height: 150),
                    rotation: 0,
                    createdAt: Date()
                )
            ],
            imageAssets: [assetPath: imageData]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        let data = try encoder.encode(payload)

        // Must match SelectionPasteboard.pasteboardType in the app target.
        UIPasteboard.general.setData(
            data,
            forPasteboardType: "com.luiz.vellum.canvas-selection"
        )
    }

    private func renderedPhotoData() throws -> Data {
        let width = 400
        let height = 300
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
        return try XCTUnwrap(image.pngData(), "failed to render the seeded photo")
    }
}

private struct PasteboardPayload: Encodable {
    let drawingData: Data
    let elements: [CanvasElementPayload]
    let imageAssets: [String: Data]
}

private struct CanvasElementPayload: Encodable {
    let id: UUID
    let kind: String
    let image: ImageContentPayload
    let frame: CanvasRectPayload
    let rotation: Double
    let createdAt: Date
}

private struct ImageContentPayload: Encodable {
    let assetPath: String
    let originalPixelSize: CanvasSizePayload
}

private struct CanvasRectPayload: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private struct CanvasSizePayload: Encodable {
    let width: Double
    let height: Double
}
