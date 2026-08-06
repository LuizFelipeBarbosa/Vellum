import XCTest

@MainActor
final class AutoTitleFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// End-to-end auto-title: the seeded untitled note already holds a typed
    /// text element ("-vellum-autotitle-seed-note", see VellumAppModel), so one
    /// ink stroke is enough to trigger save → recognition → apply. XCUITest
    /// cannot create a canvas text box directly: without -vellum-force-pencil-only
    /// the simulator canvas treats synthesized touches as ink input, so taps
    /// never reach the SwiftUI add-text layer.
    func testSeededTypedNoteAutoTitlesAfterInkStroke() {
        let app = XCUIApplication()
        app.launchArguments += ["-vellum-autotitle-seed-note"]
        app.launch()

        let untitledCard = app.staticTexts["Untitled"].firstMatch
        XCTAssertTrue(
            untitledCard.waitForExistence(timeout: 10),
            "Seeded untitled note did not appear in the library"
        )
        untitledCard.tap()

        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 10),
            "App window did not appear"
        )
        // Let the note screen settle before synthesizing touches: a stroke
        // drawn during the open transition can miss the canvas entirely.
        let titleField = app.textFields["note-screen-title-field"]
        XCTAssertTrue(
            titleField.waitForExistence(timeout: 10),
            "Note header did not appear"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        ShapeFlowTestHelpers.selectTool("Pen", in: app)

        // A short stroke low on the page: below the typed element so any stray
        // Vision reading of it sorts after the real first sentence, and with no
        // dwell so shape snap never converts the ink to a shape element (which
        // would leave the drawing — and the recognition fingerprint — unchanged).
        func drawTriggerStroke(offsetY: CGFloat) {
            let drew = ShapeFlowTestHelpers.drawStroke(
                in: app,
                window: window,
                through: [
                    CGPoint(x: 420, y: 760 + offsetY),
                    CGPoint(x: 520, y: 770 + offsetY)
                ],
                holdDuration: 0.05
            )
            XCTAssertTrue(drew, "Failed to synthesize the ink stroke")
        }
        drawTriggerStroke(offsetY: 0)

        // 600 ms save debounce + 2 s recognition debounce + Vision, then the
        // open-note apply updates the header title live. If the first stroke
        // was lost to touch-synthesis flakiness, a second stroke re-arms the
        // pipeline (new fingerprint, new recognition).
        var titleAppeared = waitUntil(timeout: 15) {
            (titleField.value as? String) == "Team retro notes"
        }
        if !titleAppeared {
            drawTriggerStroke(offsetY: 30)
            titleAppeared = waitUntil(timeout: 15) {
                (titleField.value as? String) == "Team retro notes"
            }
        }
        XCTAssertTrue(
            titleAppeared,
            "Header title never became 'Team retro notes' (value: \(String(describing: titleField.value)))"
        )

        let libraryBackButton = app.buttons["Library"]
        XCTAssertTrue(
            libraryBackButton.waitForExistence(timeout: 5),
            "Library back button did not appear"
        )
        libraryBackButton.tap()

        // Entering the library refreshes it; the card should carry the new title.
        let titledCard = app.staticTexts["Team retro notes"].firstMatch
        XCTAssertTrue(
            titledCard.waitForExistence(timeout: 10),
            "Auto-titled card never appeared in the library"
        )
        // No teardown: the seed hook purges the tagged fixture on next launch.
    }

    private func waitUntil(
        timeout: TimeInterval,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return true
    }
}
