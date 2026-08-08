import XCTest

@MainActor
final class OrganizeBadgeFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// End-to-end auto-analyze: leaving the seeded typed note (≥80 chars once
    /// recognized) for the library fires the quiet-point auto-analyze trigger;
    /// reopening the note must show the Organize chip's pending-count badge.
    /// (The pane's Close button only exists in split layouts, so the library
    /// navigation is the single-pane trigger.) `-vellum-heuristic-ai` forces
    /// the deterministic heuristic agent so proposals exist without Apple
    /// Intelligence.
    func testAutoAnalysisAfterLeavingNoteShowsOrganizeBadge() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-vellum-autotitle-seed-note",
            "-vellum-heuristic-ai"
        ]
        app.launch()

        let untitledCard = app.staticTexts["Untitled"].firstMatch
        XCTAssertTrue(
            untitledCard.waitForExistence(timeout: 10),
            "Seeded untitled note did not appear in the library"
        )
        untitledCard.tap()

        let titleField = app.textFields["note-screen-title-field"]
        XCTAssertTrue(
            titleField.waitForExistence(timeout: 10),
            "Note header did not appear"
        )

        // Recognition populates plainText (and the auto-title proves it): the
        // seeded note has never been recognized, so draw one ink stroke to
        // trigger save → recognition, exactly like the auto-title flow.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        // Re-tapping an already-selected tool opens its options popover, which
        // swallows the trigger strokes — only select Pen when it isn't active.
        let penTool = app.buttons["Pen"]
        if !(penTool.waitForExistence(timeout: 5) && penTool.isSelected) {
            ShapeFlowTestHelpers.selectTool("Pen", in: app)
        }
        func drawTriggerStroke(offsetY: CGFloat) {
            let drew = ShapeFlowTestHelpers.drawStroke(
                in: app,
                window: app.windows.firstMatch,
                through: [
                    CGPoint(x: 420, y: 760 + offsetY),
                    CGPoint(x: 520, y: 770 + offsetY)
                ],
                holdDuration: 0.05
            )
            XCTAssertTrue(drew, "Failed to synthesize the ink stroke")
        }
        drawTriggerStroke(offsetY: 0)
        var recognitionLanded = waitUntil(timeout: 15) {
            (titleField.value as? String) == "Team retro notes"
        }
        if !recognitionLanded {
            drawTriggerStroke(offsetY: 30)
            recognitionLanded = waitUntil(timeout: 15) {
                (titleField.value as? String) == "Team retro notes"
            }
        }
        XCTAssertTrue(recognitionLanded, "Recognition never populated the note text")

        // Navigating back to the library fires the auto-analyze trigger with
        // the recognized text now past the 80-char content floor.
        let libraryBackButton = app.buttons["Library"]
        XCTAssertTrue(
            libraryBackButton.waitForExistence(timeout: 5),
            "Library back button did not appear"
        )
        libraryBackButton.tap()

        let titledCard = app.staticTexts["Team retro notes"].firstMatch
        XCTAssertTrue(
            titledCard.waitForExistence(timeout: 10),
            "Auto-titled card did not appear in the library"
        )
        titledCard.tap()

        // The badge contract: the Organize button carries an accessibility
        // value like "3 suggestions" only when pending proposals exist. The
        // reopened note either lists the close-run's proposals or the open
        // trigger re-analyzes — both end with a non-zero pending count.
        let organizeButton = app.buttons["Organize"]
        XCTAssertTrue(
            organizeButton.waitForExistence(timeout: 10),
            "Organize chip did not appear"
        )
        let badgeAppeared = waitUntil(timeout: 20) {
            (organizeButton.value as? String)?.contains("suggestion") == true
        }
        XCTAssertTrue(
            badgeAppeared,
            "Organize badge never appeared (value: \(String(describing: organizeButton.value)))"
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
