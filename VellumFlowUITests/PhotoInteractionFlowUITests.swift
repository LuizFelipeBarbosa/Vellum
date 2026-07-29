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

    func testSelectedPhotoStripHasArrangeAndLacksStyleAndPaste() throws {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")

        _ = try seedPhoto(in: app, window: window)

        XCTAssertTrue(
            app.buttons["Arrange selection"].exists,
            "the selected photo's action strip did not include Arrange"
        )
        XCTAssertFalse(
            app.buttons["Style selection"].exists,
            "the selected photo's action strip unexpectedly included Style"
        )
        XCTAssertFalse(
            app.buttons["Paste selection"].exists,
            "the selected photo's action strip still included the removed Paste action"
        )
    }

    func testSelectedPhotoCanMoveAcrossInkZOrder() throws {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")

        ShapeFlowTestHelpers.selectTool("Pen", in: app)
        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.62)
        ).press(
            forDuration: 0.05,
            thenDragTo: window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.45, dy: 0.62)
            )
        )

        _ = try seedPhoto(in: app, window: window)

        let arrangeSelection = app.buttons["Arrange selection"]
        XCTAssertTrue(
            arrangeSelection.waitForExistence(timeout: 5),
            "Arrange did not appear for the selected photo"
        )
        arrangeSelection.tap()

        let bringToFront = app.buttons["Bring selection to front"]
        XCTAssertTrue(
            bringToFront.waitForExistence(timeout: 5),
            "Bring to Front did not appear in the Arrange popover"
        )
        XCTAssertTrue(
            bringToFront.isEnabled,
            "Bring to Front was disabled for a photo-only selection"
        )
        bringToFront.tap()
        assertResizeHandlesAppear(in: app)

        // Arrange actions deliberately keep the popover open for repeated taps, so
        // Send to Back is reachable directly — re-tapping Arrange would close it.
        let sendToBack = app.buttons["Send selection to back"]
        XCTAssertTrue(
            sendToBack.waitForExistence(timeout: 5),
            "Send to Back did not appear in the Arrange popover"
        )
        XCTAssertTrue(
            sendToBack.isEnabled,
            "Send to Back was disabled for a photo-only selection"
        )
        sendToBack.tap()
        assertResizeHandlesAppear(in: app)
    }

    private func seedPhoto(
        in app: XCUIApplication,
        window: XCUIElement
    ) throws -> CGVector {
        try writePhotoPayloadToPasteboard()

        ShapeFlowTestHelpers.selectTool("Select", in: app)
        clearElement(
            at: CGVector(dx: 0.35, dy: 0.62),
            in: app,
            window: window
        )
        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.35, dy: 0.62)
        ).tap()

        let pasteHere = app.buttons["Paste here"]
        XCTAssertTrue(
            pasteHere.waitForExistence(timeout: 5),
            "Paste here did not appear after tapping empty canvas"
        )
        pasteHere.tap()

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

    /// Leftover elements from earlier test runs can occupy the seed point because the
    /// Site Notes document persists across runs. Clear any selected element there so
    /// the next tap can raise the paste bubble; ink is not hit-tested by this tap path.
    private func clearElement(
        at point: CGVector,
        in app: XCUIApplication,
        window: XCUIElement,
        maxAttempts: Int = 5
    ) {
        let deleteSelection = app.buttons["Delete selection"]
        for _ in 0..<maxAttempts {
            window.coordinate(withNormalizedOffset: point).tap()
            guard deleteSelection.waitForExistence(timeout: 1.5) else { return }

            deleteSelection.tap()
            _ = deleteSelection.waitForNonExistence(timeout: 1.5)
        }
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
