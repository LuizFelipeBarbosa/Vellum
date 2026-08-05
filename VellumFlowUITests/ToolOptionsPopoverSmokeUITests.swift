import XCTest

// Guards the .popover(item:) tool-options presentation (second tap on a
// selected tool). The paper-options popover has its own coverage in
// PageOrientationFlowUITests; this is the only test that exercises the
// item-based path, which historically broke when the tool-button labels
// gained captioned/organic treatments (see the PR #18 deviation note).
@MainActor
final class ToolOptionsPopoverSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSecondTapOnPenOpensToolOptionsPopover() {
        let app = XCUIApplication()
        app.launchArguments = ["-vellum-auto-open-note"]
        app.launch()

        let toolbarToggle = app.buttons.matching(
            NSPredicate(format: "label == 'Expand toolbar' OR label == 'Collapse toolbar'")
        ).firstMatch
        XCTAssertTrue(toolbarToggle.waitForExistence(timeout: 10), "Toolbar did not render")

        let expand = app.buttons["Expand toolbar"]
        if expand.exists {
            expand.tap()
        }

        // Park on a different tool first so the "Pen" taps are deterministic:
        // first tap selects, second tap (on the selected tool) opens options.
        let pencil = app.buttons["Pencil"].firstMatch
        XCTAssertTrue(pencil.waitForExistence(timeout: 5), "Pencil tool button not found")
        pencil.tap()

        let pen = app.buttons["Pen"].firstMatch
        XCTAssertTrue(pen.waitForExistence(timeout: 5), "Pen tool button not found")
        pen.tap()
        pen.tap()

        XCTAssertTrue(
            app.staticTexts["Pen Options"].waitForExistence(timeout: 5),
            "Tool options popover did not appear"
        )
    }
}
