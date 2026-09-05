import XCTest

/// Manual evidence collection for the live model and its fallback behavior.
/// Run with the VellumRealModelQA scheme and review its result attachments;
/// a passing run alone does not prove that Apple Intelligence was available.
@MainActor
final class RealModelQAFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testRecognitionAndAutoTitleWithRealModels() {
        let app = XCUIApplication()
        _ = seedRecognizedNote(app)
    }

    func testAskSheetWithRealModel() {
        let app = XCUIApplication()
        _ = seedRecognizedNote(app)

        let askButton = app.buttons["note-ask-button"]
        let askButtonAppeared = askButton.waitForExistence(timeout: 5)
        XCTAssertTrue(askButtonAppeared, "Ask chip did not appear")
        guard askButtonAppeared else {
            attachNote("The Ask chip was absent; the Ask evidence pass could not continue.")
            snap(app, "Ask - chip unavailable")
            return
        }
        askButton.tap()

        let textField = app.textFields["note-ask-input"]
        let textView = app.textViews["note-ask-input"]
        let genericInput = app.descendants(matching: .any)["note-ask-input"]
        let questionInput: XCUIElement
        if textField.waitForExistence(timeout: 10) {
            questionInput = textField
        } else if textView.waitForExistence(timeout: 3) {
            questionInput = textView
        } else {
            questionInput = genericInput
        }

        let inputAppeared = questionInput.waitForExistence(timeout: 3)
        XCTAssertTrue(inputAppeared, "Ask sheet input did not appear")
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        snap(app, "Ask - sheet opened and model availability visible")
        guard inputAppeared else {
            attachNote("The Ask input was absent; no question could be submitted.")
            return
        }

        let textBeforeSubmission = staticTextSignature(in: app)
        questionInput.tap()
        questionInput.typeText("What did the team praise?")

        let sendButton = app.buttons["Send question"]
        let sendButtonAppeared = sendButton.waitForExistence(timeout: 5)
        XCTAssertTrue(sendButtonAppeared, "Ask sheet send button did not appear")
        guard sendButtonAppeared else {
            attachNote("The Send question button was absent; the question could not be submitted.")
            return
        }
        attachNote(
            "Send question button enabled before tap: \(sendButton.isEnabled)",
            name: "Ask - send button state"
        )
        sendButton.tap()
        captureStreamingAnswer(
            in: app,
            textBeforeSubmission: textBeforeSubmission
        )

        let summarizeButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "ummar")
        ).firstMatch
        if summarizeButton.exists {
            summarizeButton.tap()
            let summaryAppeared = waitUntil(timeout: 60) {
                app.staticTexts["Summary"].exists
            }
            if !summaryAppeared {
                attachNote("The summarize affordance was tapped, but no Summary card appeared.")
            }
            snap(app, "Ask - summary result")
        } else {
            attachNote("No summarize affordance was present after the answer settled.")
        }

        let citationButton = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "Page",
                "p."
            )
        ).firstMatch
        if citationButton.exists {
            citationButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            snap(app, "Ask - first citation opened")
        } else {
            attachNote("No citation button with a Page or p. label was present.")
        }
    }

    func testOrganizeProposalsWithRealAgent() {
        let app = XCUIApplication()
        let titleField = seedRecognizedNote(app)
        let observedTitle = titleField.value as? String

        let libraryButton = app.buttons["Library"]
        let libraryButtonAppeared = libraryButton.waitForExistence(timeout: 5)
        XCTAssertTrue(libraryButtonAppeared, "Library back button did not appear")
        guard libraryButtonAppeared else {
            attachNote("The Library button was absent; auto-analysis could not be triggered.")
            snap(app, "Organize - library navigation unavailable")
            return
        }
        libraryButton.tap()

        let expectedCard = app.staticTexts["Team retro notes"].firstMatch
        var cardToOpen = expectedCard
        if !expectedCard.waitForExistence(timeout: 10) {
            attachNote(
                "The expected Team retro notes card was absent after recognition. "
                    + "Observed title: \(observedTitle ?? "<nil>")."
            )
            if let observedTitle, !observedTitle.isEmpty {
                cardToOpen = app.staticTexts[observedTitle].firstMatch
            }
            if !cardToOpen.exists {
                cardToOpen = app.staticTexts["Untitled"].firstMatch
            }
        }

        let cardAppeared = cardToOpen.waitForExistence(timeout: 5)
        XCTAssertTrue(cardAppeared, "The seeded note card did not appear in the library")
        guard cardAppeared else {
            snap(app, "Organize - seeded card unavailable")
            return
        }
        cardToOpen.tap()

        let organizeButton = app.buttons["Organize"]
        let organizeButtonAppeared = organizeButton.waitForExistence(timeout: 10)
        XCTAssertTrue(organizeButtonAppeared, "Organize chip did not appear")
        guard organizeButtonAppeared else {
            snap(app, "Organize - chip unavailable")
            return
        }

        let badgeAppeared = waitUntil(timeout: 60) {
            (organizeButton.value as? String)?.contains("suggestion") == true
        }
        if !badgeAppeared {
            attachNote(
                "The Organize badge did not appear within 60 seconds. "
                    + "Observed value: \(String(describing: organizeButton.value))."
            )
        }
        snap(app, "Organize - real-agent suggestion badge")

        organizeButton.tap()
        let suggestionsHeading = app.staticTexts["Suggestions"]
        if !suggestionsHeading.waitForExistence(timeout: 5) {
            let reviewButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "suggestion")
            ).firstMatch
            if reviewButton.waitForExistence(timeout: 60) {
                reviewButton.tap()
            } else {
                attachNote(
                    "Neither the suggestions overlay nor its review affordance appeared "
                        + "after tapping Organize."
                )
            }
        }
        _ = suggestionsHeading.waitForExistence(timeout: 10)
        snap(app, "Organize - model-generated proposals overlay")

        let tagProposalTitle = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Add tag")
        ).firstMatch
        let acceptButtons = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Accept")
        )
        var acceptButton: XCUIElement?

        if tagProposalTitle.exists {
            let tagTitleMinY = tagProposalTitle.frame.minY
            var closestDelta = CGFloat.greatestFiniteMagnitude

            for candidate in acceptButtons.allElementsBoundByIndex {
                let delta = candidate.frame.minY - tagTitleMinY
                if delta >= 0, delta < closestDelta {
                    acceptButton = candidate
                    closestDelta = delta
                }
            }
        } else {
            attachNote("No tag proposal with a title beginning with 'Add tag' appeared.")
        }

        if acceptButton == nil {
            let genericAcceptButton = acceptButtons.firstMatch
            if genericAcceptButton.exists {
                attachNote(
                    "A tag-specific Accept button could not be resolved; "
                        + "the first generic Accept button was used as a fallback."
                )
                acceptButton = genericAcceptButton
            }
        }

        if let acceptButton {
            acceptButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))

            let closeSuggestions = app.buttons["Close suggestions"]
            if closeSuggestions.exists {
                closeSuggestions.tap()
            }

            let returnToLibrary = app.buttons["Library"]
            if returnToLibrary.waitForExistence(timeout: 5) {
                returnToLibrary.tap()
                let teamRetroCard = app.staticTexts["Team retro notes"].firstMatch
                _ = teamRetroCard.waitForExistence(timeout: 10)
                snap(app, "Organize - library after accepting first proposal")

                let tagChips = app.descendants(matching: .any).matching(
                    NSPredicate(format: "label BEGINSWITH %@", "Tags:")
                )
                let firstTagChip = tagChips.firstMatch
                if firstTagChip.waitForExistence(timeout: 5), teamRetroCard.exists {
                    let cardTitleFrame = teamRetroCard.frame
                    let nearbyTagChips = tagChips.allElementsBoundByIndex.filter { element in
                        let frame = element.frame
                        let verticalDelta = frame.minY - cardTitleFrame.minY
                        return verticalDelta >= -40
                            && verticalDelta <= 180
                            && abs(frame.midX - cardTitleFrame.midX) <= 260
                    }
                    if let tagChip = nearbyTagChips.min(by: { lhs, rhs in
                        abs(lhs.frame.minY - cardTitleFrame.minY)
                            < abs(rhs.frame.minY - cardTitleFrame.minY)
                    }) {
                        attachNote(
                            tagChip.label,
                            name: "Organize - Team retro notes tag chip"
                        )
                    } else {
                        attachNote(
                            "A Tags: element existed, but none was near the Team retro notes card."
                        )
                    }
                } else {
                    attachNote("No Tags: accessibility element was found near Team retro notes.")
                }
            } else {
                attachNote("The Library button was absent after accepting a proposal.")
                snap(app, "Organize - accepted proposal before library return")
            }
        } else {
            attachNote("No Accept button was present in the suggestions overlay.")
        }
    }

    func testSettingsIntelligenceToggle() {
        let app = XCUIApplication()
        app.launch()

        var settingsOpened = false
        let settingsButton = app.buttons["settings"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            settingsOpened = true
        } else {
            let settingsText = app.staticTexts["settings"]
            if settingsText.waitForExistence(timeout: 3) {
                settingsText.tap()
                settingsOpened = true
            } else {
                let capitalizedSettingsButton = app.buttons["Settings"]
                if capitalizedSettingsButton.waitForExistence(timeout: 3) {
                    capitalizedSettingsButton.tap()
                    settingsOpened = true
                }
            }
        }

        XCTAssertTrue(settingsOpened, "Sidebar settings control did not appear")
        guard settingsOpened else {
            attachNote("The settings control was absent.")
            snap(app, "Settings - control unavailable")
            return
        }

        let intelligenceSection = app.staticTexts["INTELLIGENCE"]
        let suggestOrganization = app.buttons["Suggest organization"]
        let settingsScrollView = app.scrollViews.firstMatch
        _ = suggestOrganization.waitForExistence(timeout: 5)
        for _ in 0..<4 {
            if intelligenceSection.isHittable && suggestOrganization.isHittable {
                break
            }
            guard settingsScrollView.exists else { break }
            settingsScrollView.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTAssertTrue(
            intelligenceSection.exists && suggestOrganization.exists,
            "Settings did not expose the Intelligence organization toggle"
        )
        snap(app, "Settings - Intelligence and Suggest organization")
    }

    private func seedRecognizedNote(_ app: XCUIApplication) -> XCUIElement {
        app.launchArguments += ["-vellum-autotitle-seed-note"]
        app.launch()

        let titleField = app.textFields["note-screen-title-field"]
        let untitledCard = app.staticTexts["Untitled"].firstMatch
        let untitledCardAppeared = untitledCard.waitForExistence(timeout: 10)
        XCTAssertTrue(
            untitledCardAppeared,
            "Seeded untitled note did not appear in the library"
        )
        guard untitledCardAppeared else {
            attachNote("The seeded Untitled card was absent.")
            snap(app, "Recognition - seeded card unavailable")
            return titleField
        }
        untitledCard.tap()

        let titleFieldAppeared = titleField.waitForExistence(timeout: 10)
        XCTAssertTrue(titleFieldAppeared, "Note header did not appear")
        guard titleFieldAppeared else {
            attachNote("The note title field was absent after opening the seeded card.")
            snap(app, "Recognition - title field unavailable")
            return titleField
        }

        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        snap(app, "Recognition - before trigger stroke")

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

        snap(app, "Recognition - after real-model auto-title")
        let observedTitle = titleField.value as? String
        attachNote(
            "Expected title: Team retro notes\n"
                + "Observed title: \(observedTitle ?? "<nil>")\n"
                + "Matched expected title: \(recognitionLanded)",
            name: "Recognition - observed auto-title"
        )
        return titleField
    }

    private func captureStreamingAnswer(
        in app: XCUIApplication,
        textBeforeSubmission: String
    ) {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(90)
        var previousText = textBeforeSubmission
        var lastTextChange = startedAt
        var snappedAtFiveSeconds = false
        var snappedAtFifteenSeconds = false

        while Date() < deadline {
            let now = Date()
            let elapsed = now.timeIntervalSince(startedAt)
            if !snappedAtFiveSeconds && elapsed >= 5 {
                snap(app, "Ask - streaming answer at 5 seconds")
                snappedAtFiveSeconds = true
            }
            if !snappedAtFifteenSeconds && elapsed >= 15 {
                snap(app, "Ask - streaming answer at 15 seconds")
                snappedAtFifteenSeconds = true
            }

            let currentText = staticTextSignature(in: app)
            if currentText != previousText {
                previousText = currentText
                lastTextChange = now
            }

            let submissionChangedText = currentText != textBeforeSubmission
            let readingIndicatorIsGone = !app.staticTexts["reading this note…"].exists
            let textHasSettled = now.timeIntervalSince(lastTextChange) >= 4
            if snappedAtFifteenSeconds,
               submissionChangedText,
               readingIndicatorIsGone,
               textHasSettled {
                snap(app, "Ask - answer settled")
                attachNote(
                    previousText,
                    name: "Ask - settled accessibility text"
                )
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        if !snappedAtFiveSeconds {
            snap(app, "Ask - streaming answer at 5 seconds")
        }
        if !snappedAtFifteenSeconds {
            snap(app, "Ask - streaming answer at 15 seconds")
        }
        snap(app, "Ask - answer after 90-second timeout")
        attachNote(
            previousText,
            name: "Ask - accessibility text at timeout"
        )
    }

    private func staticTextSignature(in app: XCUIApplication) -> String {
        app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func attachNote(_ text: String, name: String = "QA observation") {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
