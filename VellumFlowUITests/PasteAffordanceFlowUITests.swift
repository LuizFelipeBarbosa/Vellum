import UIKit
import UniformTypeIdentifiers
import XCTest

@MainActor
final class PasteAffordanceFlowUITests: XCTestCase {
    private static let topLeftHandleLabel = "Resize handle, top left corner"
    private static let bottomRightHandleLabel = "Resize handle, bottom right corner"
    private static let pastePoint = CGVector(dx: 0.72, dy: 0.68)
    private static let selectionDismissPoint = CGVector(dx: 0.70, dy: 0.25)

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEmptyTapShowsPasteHereAndPastesAtPoint() throws {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")

        let tappedScreenPoint = window.coordinate(
            withNormalizedOffset: Self.pastePoint
        ).screenPoint
        let pasteHere = showPasteBubble(
            in: app,
            window: window,
            at: Self.pastePoint
        )
        pasteHere.tap()

        ShapeFlowTestHelpers.allowPastePermission(in: app)

        let topLeft = resizeHandle(label: Self.topLeftHandleLabel, in: app)
        let bottomRight = resizeHandle(label: Self.bottomRightHandleLabel, in: app)
        XCTAssertTrue(
            topLeft.waitForExistence(timeout: 5),
            "the pasted stroke's top-left resize handle did not appear"
        )
        XCTAssertTrue(
            bottomRight.waitForExistence(timeout: 5),
            "the pasted stroke's bottom-right resize handle did not appear"
        )

        let pastedCenter = CGPoint(
            x: (topLeft.frame.midX + bottomRight.frame.midX) / 2,
            y: (topLeft.frame.midY + bottomRight.frame.midY) / 2
        )
        let distanceFromTap = hypot(
            pastedCenter.x - tappedScreenPoint.x,
            pastedCenter.y - tappedScreenPoint.y
        )
        XCTAssertLessThanOrEqual(
            distanceFromTap,
            60,
            "the pasted stroke was not centered near the empty-canvas tap"
        )
    }

    func testNoBubbleWithoutPayload() throws {
        UIPasteboard.general.items = []

        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")

        ShapeFlowTestHelpers.selectTool("Select", in: app)
        ShapeFlowTestHelpers.clearElement(
            at: CGVector(dx: 0.70, dy: 0.20),
            in: app,
            window: window
        )
        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.70, dy: 0.20)
        ).tap()

        XCTAssertFalse(
            app.buttons["Paste here"].waitForExistence(timeout: 2),
            "Paste here appeared without a Vellum pasteboard payload"
        )
    }

    func testSystemImagePasteLandsImageElement() throws {
        UIPasteboard.general.items = []
        let imageSize = CGSize(width: 40, height: 40)
        let image = UIGraphicsImageRenderer(size: imageSize).image { context in
            context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: imageSize))
        }
        let imageData = try XCTUnwrap(image.pngData())
        UIPasteboard.general.setData(
            imageData,
            forPasteboardType: UTType.png.identifier
        )

        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")

        // Low enough that the ~60%-of-viewport fitted image leaves room for the action
        // strip above the selection; near the top the strip lands under the app's own
        // Organize/Share chrome and its Delete button becomes untappable.
        let pastePoint = CGVector(dx: 0.70, dy: 0.45)
        ShapeFlowTestHelpers.selectTool("Select", in: app)
        ShapeFlowTestHelpers.clearElement(
            at: pastePoint,
            in: app,
            window: window
        )
        // The inline cleanup below never runs when an assertion fails first, and a
        // leftover pasted image poisons every later test on this persistent document.
        addTeardownBlock { @MainActor in
            UIPasteboard.general.items = []
            // A pending permission alert swallows the cleanup taps below.
            ShapeFlowTestHelpers.allowPastePermission(in: app, timeout: 2)
            ShapeFlowTestHelpers.clearElement(
                at: pastePoint,
                in: app,
                window: window
            )
        }
        window.coordinate(withNormalizedOffset: pastePoint).tap()

        let pasteHere = app.buttons["Paste here"]
        XCTAssertTrue(
            pasteHere.waitForExistence(timeout: 5),
            "Paste here did not appear after tapping empty canvas with a system image"
        )
        pasteHere.tap()

        ShapeFlowTestHelpers.allowPastePermission(in: app)

        let topLeft = resizeHandle(label: Self.topLeftHandleLabel, in: app)
        let bottomRight = resizeHandle(label: Self.bottomRightHandleLabel, in: app)
        XCTAssertTrue(
            topLeft.waitForExistence(timeout: 5),
            "the pasted image's top-left resize handle did not appear"
        )
        XCTAssertTrue(
            bottomRight.waitForExistence(timeout: 5),
            "the pasted image's bottom-right resize handle did not appear"
        )

        let deleteSelection = app.buttons["Delete selection"]
        XCTAssertTrue(
            deleteSelection.waitForExistence(timeout: 5),
            "Delete selection did not appear for the pasted image"
        )
        deleteSelection.tap()
        XCTAssertTrue(
            topLeft.waitForNonExistence(timeout: 5),
            "the pasted image's top-left resize handle remained after cleanup"
        )
        XCTAssertTrue(
            bottomRight.waitForNonExistence(timeout: 5),
            "the pasted image's bottom-right resize handle remained after cleanup"
        )
        XCTAssertTrue(
            deleteSelection.waitForNonExistence(timeout: 5),
            "Delete selection remained visible after cleaning up the pasted image"
        )
    }

    func testToolSwitchDismissesBubble() throws {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")

        _ = showPasteBubble(
            in: app,
            window: window,
            at: Self.pastePoint
        )

        ShapeFlowTestHelpers.selectTool("Pen", in: app)

        XCTAssertTrue(
            app.buttons["Paste here"].waitForNonExistence(timeout: 5),
            "Paste here remained visible after switching tools"
        )
    }

    private func showPasteBubble(
        in app: XCUIApplication,
        window: XCUIElement,
        at pastePoint: CGVector
    ) -> XCUIElement {
        ShapeFlowTestHelpers.selectTool("Pen", in: app)
        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45)
        ).press(
            forDuration: 0.05,
            thenDragTo: window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45)
            )
        )

        ShapeFlowTestHelpers.boxSelect(
            in: app,
            window: window,
            around: CGRect(
                x: window.frame.width * 0.21,
                y: window.frame.height * 0.40,
                width: window.frame.width * 0.18,
                height: window.frame.height * 0.10
            )
        )

        let copySelection = app.buttons["Copy selection"]
        XCTAssertTrue(
            copySelection.waitForExistence(timeout: 5),
            "Copy selection did not appear after box-selecting the stroke"
        )
        copySelection.tap()

        ShapeFlowTestHelpers.allowPastePermission(in: app)

        // Copy preserves the selection, so the first outside tap only deselects it.
        window.coordinate(
            withNormalizedOffset: Self.selectionDismissPoint
        ).tap()
        XCTAssertTrue(
            copySelection.waitForNonExistence(timeout: 5),
            "the copied stroke remained selected after tapping outside it"
        )

        ShapeFlowTestHelpers.selectTool("Select", in: app)
        ShapeFlowTestHelpers.clearElement(
            at: pastePoint,
            in: app,
            window: window
        )
        window.coordinate(withNormalizedOffset: pastePoint).tap()

        let pasteHere = app.buttons["Paste here"]
        XCTAssertTrue(
            pasteHere.waitForExistence(timeout: 5),
            "Paste here did not appear after tapping empty canvas with copied content"
        )
        return pasteHere
    }

    private func resizeHandle(label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }
}
