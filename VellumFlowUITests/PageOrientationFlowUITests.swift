import XCTest

@MainActor
final class PageOrientationFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPaperOptionsChangesPageOrientation() {
        let context = launchApp(shouldOpenSiteNotes: true)
        openPaperOptions(in: context.app)

        let orientationControl = context.app.segmentedControls["Page orientation"]
        XCTAssertTrue(
            orientationControl.waitForExistence(timeout: 5),
            "Page orientation control not found, state: "
                + stateString(of: context.stateElement)
        )

        setOrientation(
            "Portrait",
            expectedValue: "portrait",
            in: context.app,
            stateElement: context.stateElement
        )
        addTeardownBlock { @MainActor in
            self.restorePortrait(
                in: context.app,
                stateElement: context.stateElement
            )
        }

        setOrientation(
            "Landscape",
            expectedValue: "landscape",
            in: context.app,
            stateElement: context.stateElement
        )

        setOrientation(
            "Portrait",
            expectedValue: "portrait",
            in: context.app,
            stateElement: context.stateElement
        )
    }

    func testPDFBackedNoteHidesPageOrientationControl() {
        let context = launchApp(arguments: ["-vellum-pdf-fixture-note"])
        openPaperOptions(in: context.app)

        let orientationElements = context.app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Page orientation")
        )
        XCTAssertEqual(
            orientationElements.count,
            0,
            "PDF-backed note exposed a Page orientation control, state: "
                + stateString(of: context.stateElement)
        )
        XCTAssertTrue(
            context.app.staticTexts["Page size follows the imported PDF."]
                .waitForExistence(timeout: 5),
            "PDF page-size explanation not found, state: "
                + stateString(of: context.stateElement)
        )
    }

    // MARK: - App and interaction helpers

    private func launchApp(
        arguments: [String] = [],
        shouldOpenSiteNotes: Bool = false
    ) -> (
        app: XCUIApplication,
        window: XCUIElement,
        stateElement: XCUIElement
    ) {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "app window not found")

        if shouldOpenSiteNotes {
            openSiteNotes(in: app)
        }

        let stateElement = app.otherElements["vellum-split-state"]
        XCTAssertTrue(
            stateElement.waitForExistence(timeout: 15),
            "split state accessibility element not found"
        )
        return (app, window, stateElement)
    }

    private func openSiteNotes(in app: XCUIApplication) {
        let card = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Site notes'")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Site notes card not found")
        card.tap()
    }

    private func openPaperOptions(in app: XCUIApplication) {
        let orientationControl = app.segmentedControls["Page orientation"]
        let pdfExplanation = app.staticTexts["Page size follows the imported PDF."]
        guard !orientationControl.exists, !pdfExplanation.exists else { return }

        let paperOptions = app.buttons["Paper options"]
        if !paperOptions.waitForExistence(timeout: 2) {
            let expandToolbar = app.buttons["Expand toolbar"]
            if expandToolbar.waitForExistence(timeout: 2) {
                expandToolbar.tap()
            }
        }
        XCTAssertTrue(paperOptions.waitForExistence(timeout: 5), "Paper options not found")
        paperOptions.tap()
        XCTAssertTrue(
            waitUntil { orientationControl.exists || pdfExplanation.exists },
            "Paper options popover did not appear"
        )
    }

    private func setOrientation(
        _ label: String,
        expectedValue: String,
        in app: XCUIApplication,
        stateElement: XCUIElement
    ) {
        let initialState = stateValues(of: stateElement)
        guard initialState["orientation"] != expectedValue else { return }

        let orientationControl = app.segmentedControls["Page orientation"]
        let segment = orientationControl.buttons[label]
        XCTAssertTrue(
            segment.waitForExistence(timeout: 5),
            "\(label) orientation segment not found, state: \(initialState)"
        )
        segment.tap()

        let rotate = app.buttons["Rotate"]
        if rotate.waitForExistence(timeout: 1) {
            rotate.tap()
        }

        let state = waitForState(stateElement) {
            $0["orientation"] == expectedValue
        }
        XCTAssertEqual(state["orientation"], expectedValue, "state: \(state)")
    }

    private func restorePortrait(
        in app: XCUIApplication,
        stateElement: XCUIElement
    ) {
        guard app.exists,
              stateElement.exists,
              stateValues(of: stateElement)["orientation"] == "landscape" else {
            return
        }
        openPaperOptions(in: app)
        setOrientation(
            "Portrait",
            expectedValue: "portrait",
            in: app,
            stateElement: stateElement
        )
    }

    // MARK: - Split state

    private func stateString(
        of element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        guard let value = element.value as? String else {
            XCTFail(
                "split state has unexpected value: \(String(describing: element.value))",
                file: file,
                line: line
            )
            return ""
        }
        return value
    }

    private func stateValues(
        of element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [String: String] {
        let value = stateString(of: element, file: file, line: line)
        var state: [String: String] = [:]

        for component in value.split(
            separator: ";",
            omittingEmptySubsequences: false
        ) {
            let pair = component.split(
                separator: ":",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty else {
                XCTFail(
                    "split state is malformed: \(value)",
                    file: file,
                    line: line
                )
                return [:]
            }

            let key = String(pair[0])
            guard state[key] == nil else {
                XCTFail(
                    "split state has duplicate key '\(key)': \(value)",
                    file: file,
                    line: line
                )
                return [:]
            }
            state[key] = String(pair[1])
        }
        return state
    }

    private func waitForState(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        until condition: ([String: String]) -> Bool
    ) -> [String: String] {
        let deadline = Date().addingTimeInterval(timeout)
        var lastState = stateValues(of: element)
        while !condition(lastState) {
            guard Date() < deadline else { return lastState }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            lastState = stateValues(of: element)
        }
        return lastState
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }
}
