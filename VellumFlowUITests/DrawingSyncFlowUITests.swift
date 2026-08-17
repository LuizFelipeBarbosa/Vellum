import XCTest

@MainActor
final class DrawingSyncFlowUITests: XCTestCase {
    private let drawingAreaStart = CGVector(dx: 0.18, dy: 0.30)
    private let drawingAreaEnd = CGVector(dx: 0.84, dy: 0.80)

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testModelDrivenCanvasRefreshPreservesLatestStroke() {
        let context = launchApp()
        let initialState = stateValues(of: context.stateElement)
        guard let initialOrientation = initialState["orientation"] else {
            XCTFail("split state has no orientation: \(initialState)")
            return
        }

        addTeardownBlock { @MainActor in
            self.restoreOrientation(
                initialOrientation,
                in: context.app,
                stateElement: context.stateElement
            )
            self.dismissPaperOptionsIfNeeded(
                in: context.app,
                window: context.window
            )
            if context.app.exists, context.window.exists {
                ShapeFlowTestHelpers.clearShapeDrawingArea(
                    in: context.app,
                    window: context.window,
                    selectionStart: self.drawingAreaStart,
                    selectionEnd: self.drawingAreaEnd
                )
            }
        }

        ShapeFlowTestHelpers.clearShapeDrawingArea(
            in: context.app,
            window: context.window,
            selectionStart: drawingAreaStart,
            selectionEnd: drawingAreaEnd
        )
        ShapeFlowTestHelpers.selectTool("Pen", in: context.app)

        let strokeCountElement = context.app.otherElements[
            "vellum-canvas-stroke-count"
        ]
        XCTAssertTrue(
            strokeCountElement.waitForExistence(timeout: 10),
            "canvas stroke-count accessibility element not found"
        )
        let countBeforeDrawing = strokeCount(of: strokeCountElement)

        let width = context.window.frame.width
        let height = context.window.frame.height
        XCTAssertTrue(
            ShapeFlowTestHelpers.drawStroke(
                in: context.app,
                window: context.window,
                through: [
                    CGPoint(x: width * 0.30, y: height * 0.52),
                    CGPoint(x: width * 0.42, y: height * 0.55),
                ],
                holdDuration: 0
            ),
            "first ink gesture could not be synthesized"
        )

        let countAfterFirstStroke = waitForStrokeCount(strokeCountElement) {
            $0 > countBeforeDrawing
        }
        let strokesPerGesture = countAfterFirstStroke - countBeforeDrawing
        XCTAssertGreaterThan(
            strokesPerGesture,
            0,
            "the first ink gesture created no PencilKit strokes"
        )

        XCTAssertTrue(
            ShapeFlowTestHelpers.drawStroke(
                in: context.app,
                window: context.window,
                through: [
                    CGPoint(x: width * 0.52, y: height * 0.60),
                    CGPoint(x: width * 0.65, y: height * 0.63),
                ],
                holdDuration: 0
            ),
            "second ink gesture could not be synthesized"
        )

        let expectedCountAfterTwoStrokes = countAfterFirstStroke + strokesPerGesture
        let countAfterTwoStrokes = waitForStrokeCount(strokeCountElement) {
            $0 >= expectedCountAfterTwoStrokes
        }
        XCTAssertEqual(
            countAfterTwoStrokes,
            expectedCountAfterTwoStrokes,
            "the second gesture did not contribute the same stroke count as the first"
        )

        openPaperOptions(in: context.app)
        let targetOrientation: (label: String, value: String) =
            initialOrientation == "portrait"
                ? ("Landscape", "landscape")
                : ("Portrait", "portrait")
        setOrientation(
            targetOrientation.label,
            expectedValue: targetOrientation.value,
            in: context.app,
            stateElement: context.stateElement
        )

        XCTAssertEqual(
            strokeCount(of: strokeCountElement),
            countAfterTwoStrokes,
            "a model-driven canvas refresh lost the latest stroke"
        )
    }

    // MARK: - App and interaction helpers

    private func launchApp() -> (
        app: XCUIApplication,
        window: XCUIElement,
        stateElement: XCUIElement
    ) {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "app window not found")

        let stateElement = app.otherElements["vellum-split-state"]
        XCTAssertTrue(
            stateElement.waitForExistence(timeout: 15),
            "split state accessibility element not found"
        )
        return (app, window, stateElement)
    }

    private func openPaperOptions(in app: XCUIApplication) {
        let orientationControl = app.segmentedControls["Page orientation"]
        guard !orientationControl.exists else { return }

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
            waitUntil { orientationControl.exists },
            "Paper options popover did not expose page orientation"
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

    private func restoreOrientation(
        _ orientation: String,
        in app: XCUIApplication,
        stateElement: XCUIElement
    ) {
        guard app.exists, stateElement.exists,
              stateValues(of: stateElement)["orientation"] != orientation else {
            return
        }

        openPaperOptions(in: app)
        setOrientation(
            orientation == "portrait" ? "Portrait" : "Landscape",
            expectedValue: orientation,
            in: app,
            stateElement: stateElement
        )
    }

    private func dismissPaperOptionsIfNeeded(
        in app: XCUIApplication,
        window: XCUIElement
    ) {
        let orientationControl = app.segmentedControls["Page orientation"]
        guard orientationControl.exists else { return }

        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.02, dy: 0.08)
        ).tap()
        _ = orientationControl.waitForNonExistence(timeout: 2)
    }

    // MARK: - Accessibility state

    private func strokeCount(
        of element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int {
        if let value = element.value as? String, let count = Int(value) {
            return count
        }
        if let value = element.value as? NSNumber {
            return value.intValue
        }
        XCTFail(
            "canvas stroke count has unexpected value: \(String(describing: element.value))",
            file: file,
            line: line
        )
        return -1
    }

    private func waitForStrokeCount(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        until condition: (Int) -> Bool
    ) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var lastCount = strokeCount(of: element)
        while !condition(lastCount) {
            guard Date() < deadline else { return lastCount }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            lastCount = strokeCount(of: element)
        }
        return lastCount
    }

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
