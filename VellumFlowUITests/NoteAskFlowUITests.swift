import XCTest

@MainActor
final class NoteAskFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Reuses the auto-title flow's seeded typed-note fixture and forces the
    /// keyword provider, asserting its deterministic answer shape without
    /// depending on Apple Intelligence availability.
    func testSeededNoteReturnsDeterministicKeywordAnswer() {
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

        // The seeded note has never been through recognition, so its pages
        // carry no plainText yet and the ask source would be empty. Draw one
        // ink stroke to trigger save → recognition (same as the auto-title
        // flow) and wait for the auto-title as proof the text landed.
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

        let askButton = app.buttons["note-ask-button"]
        XCTAssertTrue(
            askButton.waitForExistence(timeout: 5),
            "Ask chip did not appear"
        )
        askButton.tap()

        // Identifier-based lookup with .any: the axis-vertical TextField's
        // element type varies across SwiftUI versions.
        let questionInput = app.descendants(matching: .any)["note-ask-input"]
        XCTAssertTrue(
            questionInput.waitForExistence(timeout: 10),
            "Ask sheet input did not appear"
        )
        questionInput.tap()
        questionInput.typeText("What about the retro?")

        let sendButton = app.buttons["Send question"]
        XCTAssertTrue(
            sendButton.waitForExistence(timeout: 5),
            "Send question button did not appear"
        )
        sendButton.tap()

        let answerText = app.staticTexts.containing(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "Here's what I found in this note."
            )
        ).firstMatch
        let retroText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "retro")
        ).firstMatch
        let deterministicAnswerAppeared = waitUntil(timeout: 15) {
            answerText.exists && !answerText.label.isEmpty && retroText.exists
        }
        XCTAssertTrue(
            deterministicAnswerAppeared,
            "Keyword answer prefix and retro text did not both appear"
        )

        if questionInput.exists {
            app.swipeDown()
            if questionInput.exists {
                app.swipeDown()
            }
        }
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
