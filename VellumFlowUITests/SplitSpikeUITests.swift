import XCTest

@MainActor
final class SplitSpikeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testUndoIsolationAndFocusTracking() {
        let app = XCUIApplication()
        app.launchArguments = ["-vellum-split-spike"]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")

        let stateElement = app.otherElements["vellum-split-spike-state"]
        XCTAssertTrue(
            stateElement.waitForExistence(timeout: 10),
            "split spike state accessibility element not found"
        )

        let width = window.frame.width
        let height = window.frame.height
        let strokeAStart = CGPoint(x: width * 0.20, y: height * 0.55)
        let strokeAEnd = CGPoint(x: width * 0.32, y: height * 0.65)
        let strokeBStart = CGPoint(x: width * 0.68, y: height * 0.55)
        let strokeBEnd = CGPoint(x: width * 0.80, y: height * 0.65)

        XCTAssertTrue(
            ShapeFlowTestHelpers.drawStroke(
                in: app,
                window: window,
                through: [strokeAStart, strokeAEnd],
                holdDuration: 0.3
            ),
            "failed to synthesize the pane A ink stroke"
        )

        let stateAfterA = waitForState(stateElement) { state in
            state["strokesA"] == "1"
        }
        XCTAssertEqual(stateAfterA["strokesA"], "1", "state: \(stateAfterA)")
        XCTAssertEqual(stateAfterA["canUndoA"], "1", "state: \(stateAfterA)")
        XCTAssertEqual(stateAfterA["lastTouch"], "A", "state: \(stateAfterA)")

        XCTAssertTrue(
            ShapeFlowTestHelpers.drawStroke(
                in: app,
                window: window,
                through: [strokeBStart, strokeBEnd],
                holdDuration: 0.3
            ),
            "failed to synthesize the pane B ink stroke"
        )

        let stateAfterB = waitForState(stateElement) { state in
            state["strokesB"] == "1"
        }
        XCTAssertEqual(stateAfterB["strokesA"], "1", "state: \(stateAfterB)")
        XCTAssertEqual(stateAfterB["strokesB"], "1", "state: \(stateAfterB)")
        XCTAssertEqual(stateAfterB["canUndoA"], "1", "state: \(stateAfterB)")
        XCTAssertEqual(stateAfterB["canUndoB"], "1", "state: \(stateAfterB)")
        XCTAssertEqual(stateAfterB["lastTouch"], "B", "state: \(stateAfterB)")

        let undoA = app.buttons["Undo A"]
        XCTAssertTrue(undoA.waitForExistence(timeout: 5), "Undo A button not found")
        undoA.tap()

        let stateAfterUndoA = waitForState(stateElement) { state in
            state["strokesA"] == "0"
        }
        XCTAssertEqual(stateAfterUndoA["strokesA"], "0", "state: \(stateAfterUndoA)")
        XCTAssertEqual(stateAfterUndoA["strokesB"], "1", "state: \(stateAfterUndoA)")
        XCTAssertEqual(stateAfterUndoA["canUndoA"], "0", "state: \(stateAfterUndoA)")
        XCTAssertEqual(stateAfterUndoA["canUndoB"], "1", "state: \(stateAfterUndoA)")
    }

    func testDividerDragResizesPanes() {
        let app = XCUIApplication()
        app.launchArguments = ["-vellum-split-spike"]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")

        let stateElement = app.otherElements["vellum-split-spike-state"]
        XCTAssertTrue(
            stateElement.waitForExistence(timeout: 10),
            "split spike state accessibility element not found"
        )

        let initialState = stateValues(of: stateElement)
        guard let initialWidthAValue = initialState["widthA"],
              let initialWidthA = Int(initialWidthAValue),
              let initialWidthBValue = initialState["widthB"],
              let initialWidthB = Int(initialWidthBValue) else {
            return XCTFail("initial pane widths are invalid: \(initialState)")
        }

        let targetWidthA = initialWidthA + 150
        let dividerY = window.frame.height * 0.6
        let maximumAttempts = 20
        var attemptCount = 0
        var resizedState = initialState

        while attemptCount < maximumAttempts {
            guard let currentWidthAValue = resizedState["widthA"],
                  let currentWidthA = Int(currentWidthAValue) else {
                return XCTFail("current pane A width is invalid: \(resizedState)")
            }

            let remaining = targetWidthA - currentWidthA
            if abs(remaining) <= 10 {
                break
            }

            attemptCount += 1
            let chunkDistance = max(-30, min(30, remaining))
            let dividerX = CGFloat(currentWidthA) + 8
            let start = CGPoint(x: dividerX, y: dividerY)
            let end = CGPoint(
                x: dividerX + CGFloat(chunkDistance),
                y: dividerY
            )
            guard let record = makeSlowDividerDragGestureRecord(
                in: app,
                window: window,
                from: start,
                to: end
            ) else {
                return XCTFail("XCTest synthesized pointer support is unavailable.")
            }

            XCTAssertTrue(
                ShapeFlowTestHelpers.synthesize(record),
                "failed to synthesize divider drag attempt \(attemptCount)"
            )

            resizedState = waitForState(stateElement, timeout: 3) { state in
                guard let widthAValue = state["widthA"],
                      let widthA = Int(widthAValue) else {
                    return false
                }
                return widthA != currentWidthA
            }
        }

        guard let resizedWidthAValue = resizedState["widthA"],
              let resizedWidthA = Int(resizedWidthAValue),
              let resizedWidthBValue = resizedState["widthB"],
              let resizedWidthB = Int(resizedWidthBValue) else {
            return XCTFail("resized pane widths are invalid: \(resizedState)")
        }

        XCTAssertTrue(
            abs(targetWidthA - resizedWidthA) <= 10,
            "divider drag did not reach target widthA \(targetWidthA) "
                + "after \(attemptCount) attempts, state: \(resizedState)"
        )

        let widthAIncrease = resizedWidthA - initialWidthA
        XCTAssertTrue(
            (110...190).contains(widthAIncrease),
            "pane A width changed by \(widthAIncrease), state: \(resizedState)"
        )

        let widthBDecrease = initialWidthB - resizedWidthB
        XCTAssertTrue(
            (110...190).contains(widthBDecrease),
            "pane B width changed by \(widthBDecrease), state: \(resizedState)"
        )
    }

    private func makeSlowDividerDragGestureRecord(
        in app: XCUIApplication,
        window: XCUIElement,
        from start: CGPoint,
        to end: CGPoint
    ) -> ShapeFlowTestHelpers.GestureRecord? {
        let screenStart = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: start.x, dy: start.y))
            .screenPoint
        let screenEnd = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: end.x, dy: end.y))
            .screenPoint

        let sampleInterval: TimeInterval = 0.05
        let holdSamples = 6
        var moves: [(point: CGPoint, offset: TimeInterval)] = []
        var offset: TimeInterval = 0

        for _ in 1...holdSamples {
            offset += sampleInterval
            moves.append((point: screenStart, offset: offset))
        }

        let distance = hypot(
            screenEnd.x - screenStart.x,
            screenEnd.y - screenStart.y
        )
        let maximumStepLength: CGFloat = 5
        let movementSteps = max(1, Int(ceil(distance / maximumStepLength)))
        for index in 1...movementSteps {
            let fraction = CGFloat(index) / CGFloat(movementSteps)
            offset += sampleInterval
            moves.append(
                (
                    point: CGPoint(
                        x: screenStart.x + (screenEnd.x - screenStart.x) * fraction,
                        y: screenStart.y + (screenEnd.y - screenStart.y) * fraction
                    ),
                    offset: offset
                )
            )
        }

        for _ in 1...holdSamples {
            offset += sampleInterval
            moves.append((point: screenEnd, offset: offset))
        }

        return ShapeFlowTestHelpers.makeGestureRecord(
            named: "Slow divider drag",
            gesture: ShapeFlowTestHelpers.PointerGesture(
                start: screenStart,
                moves: moves,
                liftOffset: offset + sampleInterval
            ),
            targetProcessID: ShapeFlowTestHelpers.processID(of: app)
        )
    }

    private func stateValues(
        of element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [String: String] {
        guard let value = element.value as? String else {
            XCTFail(
                "split spike state has unexpected value: "
                    + String(describing: element.value),
                file: file,
                line: line
            )
            return [:]
        }

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
                    "split spike state is malformed: \(value)",
                    file: file,
                    line: line
                )
                return [:]
            }

            let key = String(pair[0])
            guard state[key] == nil else {
                XCTFail(
                    "split spike state has duplicate key '\(key)': \(value)",
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
}
