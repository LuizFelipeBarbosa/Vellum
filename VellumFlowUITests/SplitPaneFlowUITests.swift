import XCTest

@MainActor
final class SplitPaneFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSplitPanesLaunchArgOpensPanes() {
        let context = launchApp(splitPaneCount: 2)

        let state = waitForState(context.stateElement) { state in
            let fractions = self.fractions(from: state)
            guard state["panes"] == "2",
                  fractions.count == 2,
                  fractions.allSatisfy({ abs($0 - 0.5) <= 0.02 }),
                  let focused = state["focused"].flatMap(Int.init) else {
                return false
            }
            return (0...1).contains(focused)
        }
        let fractions = fractions(from: state)

        XCTAssertEqual(state["panes"], "2", "state: \(state)")
        XCTAssertEqual(fractions.count, 2, "state: \(state)")
        for fraction in fractions {
            XCTAssertEqual(fraction, 0.5, accuracy: 0.02, "state: \(state)")
        }
        guard let focused = state["focused"].flatMap(Int.init) else {
            return XCTFail("focused pane index is invalid: \(state)")
        }
        XCTAssertTrue((0...1).contains(focused), "state: \(state)")
    }

    func testSidebarDragCreatesPane() {
        let context = launchApp(splitPaneCount: 1)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "1"
        }
        XCTAssertEqual(initialState["panes"], "1", "state: \(initialState)")

        addTeardownBlock { @MainActor in
            self.closePanesAddedAbove(
                1,
                in: context.app,
                stateElement: context.stateElement
            )
        }

        let sidebar = showSidebar(in: context.app)
        let titleField = context.app.textFields["note-screen-title-field"].firstMatch
        XCTAssertTrue(
            titleField.waitForExistence(timeout: 5),
            "single pane title field not found"
        )

        guard let row = waitForSidebarRow(in: sidebar, matching: { label in
            label != self.displayTitle(of: titleField)
        }) else {
            return XCTFail(
                "no visible sidebar row differed from '\(displayTitle(of: titleField))'"
            )
        }
        guard let record = makeSidebarDragGestureRecord(
            in: context.app,
            window: context.window,
            row: row,
            dropOffset: CGVector(dx: 0.90, dy: 0.50)
        ) else {
            return XCTFail("XCTest synthesized pointer support is unavailable.")
        }

        XCTAssertTrue(
            ShapeFlowTestHelpers.synthesize(record),
            "failed to synthesize the sidebar note drag"
        )

        let settledState = waitForState(context.stateElement, timeout: 5) {
            $0["dragging"] == "0"
        }
        XCTAssertEqual(settledState["dragging"], "0", "state: \(settledState)")

        let createdState = waitForState(context.stateElement) {
            $0["panes"] == "2" && $0["dragging"] == "0"
        }
        XCTAssertEqual(createdState["panes"], "2", "state: \(createdState)")

        closePanesAddedAbove(
            1,
            in: context.app,
            stateElement: context.stateElement
        )
    }

    func testDragAlreadyOpenNoteFocusesPane() {
        let context = launchApp(splitPaneCount: 2)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "2" && $0["focused"].flatMap(Int.init) != nil
        }
        guard let initialFocused = initialState["focused"].flatMap(Int.init) else {
            return XCTFail("initial focused pane index is invalid: \(initialState)")
        }
        XCTAssertTrue((0...1).contains(initialFocused), "state: \(initialState)")

        let titleFields = sortedTitleFields(in: context.app, expectedCount: 2)
        guard let paneZeroTitleField = titleFields.first else {
            return XCTFail("pane 0 title field not found")
        }

        let sidebar = showSidebar(in: context.app)
        guard let row = waitForSidebarRow(in: sidebar, matching: { label in
            label == self.displayTitle(of: paneZeroTitleField)
        }) else {
            return XCTFail(
                "sidebar row for pane 0 title "
                    + "'\(displayTitle(of: paneZeroTitleField))' not found"
            )
        }
        guard let record = makeSidebarDragGestureRecord(
            in: context.app,
            window: context.window,
            row: row,
            dropOffset: CGVector(dx: 0.75, dy: 0.50)
        ) else {
            return XCTFail("XCTest synthesized pointer support is unavailable.")
        }

        XCTAssertTrue(
            ShapeFlowTestHelpers.synthesize(record),
            "failed to synthesize the already-open note drag"
        )

        let settledState = waitForState(context.stateElement, timeout: 5) {
            $0["dragging"] == "0"
        }
        XCTAssertEqual(settledState["dragging"], "0", "state: \(settledState)")

        let focusedState = waitForState(context.stateElement) {
            $0["panes"] == "2"
                && $0["focused"] == "0"
                && $0["dragging"] == "0"
        }
        XCTAssertEqual(focusedState["panes"], "2", "state: \(focusedState)")
        XCTAssertEqual(
            focusedState["focused"],
            "0",
            "initial focus was \(initialFocused), final state: \(focusedState)"
        )
    }

    func testClosePaneRenormalizesFractions() throws {
        let context = launchApp(splitPaneCount: 3)
        let initialState = waitForState(context.stateElement) {
            ($0["panes"].flatMap(Int.init) ?? 0) >= 3
        }
        guard let paneCount = initialState["panes"].flatMap(Int.init) else {
            return XCTFail("pane count is invalid: \(initialState)")
        }
        if paneCount < 3 {
            throw XCTSkip(
                "fewer than 3 panes available: \(stateString(of: context.stateElement))"
            )
        }

        let closeButtons = matchingButtons(
            labeled: "Close pane",
            in: context.app,
            expectedCount: 3
        )
        guard let rightmostClose = closeButtons.max(
            by: { $0.frame.minX < $1.frame.minX }
        ) else {
            return XCTFail("no Close pane button found")
        }
        tapByCoordinate(rightmostClose)

        let closedState = waitForState(context.stateElement) {
            $0["panes"] == "2"
        }
        let fractions = fractions(from: closedState)
        XCTAssertEqual(closedState["panes"], "2", "state: \(closedState)")
        XCTAssertEqual(fractions.count, 2, "state: \(closedState)")
        XCTAssertEqual(fractions.reduce(0, +), 1.0, accuracy: 0.02)

        let minimumFraction = 320 / Double(context.window.frame.width)
        for fraction in fractions {
            XCTAssertGreaterThanOrEqual(
                fraction,
                minimumFraction - 0.02,
                "fraction \(fraction) violates the 320pt minimum, state: \(closedState)"
            )
        }
    }

    func testDividerDragResizesAndClamps() {
        let context = launchApp(splitPaneCount: 2)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "2" && self.fractions(from: $0).count == 2
        }
        let initialFractions = fractions(from: initialState)
        guard initialFractions.count == 2 else {
            return XCTFail("initial fractions are invalid: \(initialState)")
        }

        let windowWidth = Double(context.window.frame.width)
        let dividerY = context.window.frame.height * 0.60
        let initialPaneZeroWidth = initialFractions[0] * windowWidth
        let targetPaneZeroWidth = min(
            initialPaneZeroWidth + 200,
            windowWidth - 320
        )
        let maximumPhaseAAttempts = 20
        var phaseAAttempts = 0
        var phaseAState = initialState

        while phaseAAttempts < maximumPhaseAAttempts {
            let currentFractions = fractions(from: phaseAState)
            guard currentFractions.count == 2 else {
                return XCTFail("current fractions are invalid: \(phaseAState)")
            }

            let currentPaneZeroWidth = currentFractions[0] * windowWidth
            let remaining = targetPaneZeroWidth - currentPaneZeroWidth
            if abs(remaining) <= 5 {
                break
            }

            phaseAAttempts += 1
            let chunkDistance = max(-30.0, min(30.0, remaining))
            let dividerX = currentFractions[0] * windowWidth
            guard let record = makeSlowDividerDragGestureRecord(
                in: context.app,
                window: context.window,
                from: CGPoint(x: CGFloat(dividerX), y: dividerY),
                to: CGPoint(
                    x: CGFloat(dividerX + chunkDistance),
                    y: dividerY
                )
            ) else {
                return XCTFail("XCTest synthesized pointer support is unavailable.")
            }

            XCTAssertTrue(
                ShapeFlowTestHelpers.synthesize(record),
                "failed to synthesize phase A divider drag \(phaseAAttempts)"
            )

            let previousFractions = phaseAState["fractions"]
            phaseAState = waitForState(context.stateElement, timeout: 3) {
                $0["panes"] == "2" && $0["fractions"] != previousFractions
            }
        }

        let resizedFractions = fractions(from: phaseAState)
        guard resizedFractions.count == 2 else {
            return XCTFail("resized fractions are invalid: \(phaseAState)")
        }
        let resizedPaneZeroWidth = resizedFractions[0] * windowWidth
        let paneZeroIncrease = resizedPaneZeroWidth - initialPaneZeroWidth
        XCTAssertGreaterThan(
            resizedFractions[0],
            initialFractions[0],
            "pane 0 did not grow, state: \(phaseAState)"
        )
        XCTAssertGreaterThanOrEqual(
            paneZeroIncrease,
            80,
            "pane 0 grew only \(paneZeroIncrease)pt, state: \(phaseAState)"
        )
        XCTAssertLessThanOrEqual(
            paneZeroIncrease,
            320,
            "pane 0 grew \(paneZeroIncrease)pt, state: \(phaseAState)"
        )

        let minimumFraction = 320 / windowWidth
        let maximumPhaseBAttempts = 75
        var phaseBAttempts = 0
        var requestedPhaseBDistance = 0.0
        var unchangedPolls = 0
        var phaseBState = phaseAState
        var minimumObservedFractionOne = resizedFractions[1]

        while phaseBAttempts < maximumPhaseBAttempts,
              requestedPhaseBDistance < 2_000,
              unchangedPolls < 2 {
            let currentFractions = fractions(from: phaseBState)
            guard currentFractions.count == 2 else {
                return XCTFail("phase B fractions are invalid: \(phaseBState)")
            }

            let chunkDistance = min(30.0, 2_000 - requestedPhaseBDistance)
            let dividerX = currentFractions[0] * windowWidth
            phaseBAttempts += 1
            requestedPhaseBDistance += chunkDistance

            guard let record = makeSlowDividerDragGestureRecord(
                in: context.app,
                window: context.window,
                from: CGPoint(x: CGFloat(dividerX), y: dividerY),
                to: CGPoint(
                    x: CGFloat(dividerX + chunkDistance),
                    y: dividerY
                )
            ) else {
                return XCTFail("XCTest synthesized pointer support is unavailable.")
            }

            XCTAssertTrue(
                ShapeFlowTestHelpers.synthesize(record),
                "failed to synthesize phase B divider drag \(phaseBAttempts)"
            )

            let previousFractions = phaseBState["fractions"]
            let polledState = waitForState(context.stateElement, timeout: 1.5) {
                $0["panes"] == "2" && $0["fractions"] != previousFractions
            }
            let polledFractions = fractions(from: polledState)
            guard polledFractions.count == 2 else {
                return XCTFail("polled phase B fractions are invalid: \(polledState)")
            }

            minimumObservedFractionOne = min(
                minimumObservedFractionOne,
                polledFractions[1]
            )
            if polledFractions[1] == currentFractions[1] {
                unchangedPolls += 1
            } else {
                unchangedPolls = 0
            }
            phaseBState = polledState
        }

        let finalFractions = fractions(from: phaseBState)
        guard finalFractions.count == 2 else {
            return XCTFail("final fractions are invalid: \(phaseBState)")
        }
        XCTAssertEqual(
            finalFractions[1],
            minimumFraction,
            accuracy: 0.02,
            "right pane did not settle at the 320pt clamp, state: \(phaseBState)"
        )
        XCTAssertGreaterThanOrEqual(
            minimumObservedFractionOne,
            minimumFraction - 0.01,
            "right pane moved below the clamp, state: \(phaseBState)"
        )
    }

    func testTapSidebarRowFocusesOrOpens() {
        let context = launchApp(splitPaneCount: 2)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "2"
        }
        XCTAssertEqual(initialState["panes"], "2", "state: \(initialState)")

        let titleFields = sortedTitleFields(in: context.app, expectedCount: 2)
        guard let paneOneTitleField = titleFields.last else {
            return XCTFail("pane 1 title field not found")
        }

        let sidebar = showSidebar(in: context.app)
        guard let row = waitForSidebarRow(in: sidebar, matching: { label in
            label == self.displayTitle(of: paneOneTitleField)
        }) else {
            return XCTFail(
                "sidebar row for pane 1 title "
                    + "'\(displayTitle(of: paneOneTitleField))' not found"
            )
        }
        tapByCoordinate(row)

        let focusedState = waitForState(context.stateElement) {
            $0["focused"] == "1" && $0["panes"] == "2"
        }
        XCTAssertEqual(focusedState["focused"], "1", "state: \(focusedState)")
        XCTAssertEqual(focusedState["panes"], "2", "state: \(focusedState)")
        XCTAssertTrue(
            sidebar.exists,
            "sidebar closed after tapping an already-open note row"
        )
    }

    // MARK: - App and accessibility helpers

    private func launchApp(
        splitPaneCount: Int
    ) -> (
        app: XCUIApplication,
        window: XCUIElement,
        stateElement: XCUIElement
    ) {
        let app = XCUIApplication()
        app.launchArguments = ["-vellum-split-panes", String(splitPaneCount)]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "app window not found")

        let stateElement = app.otherElements["vellum-split-state"]
        XCTAssertTrue(
            stateElement.waitForExistence(timeout: 15),
            "split state accessibility element not found"
        )
        return (app, window, stateElement)
    }

    private func showSidebar(in app: XCUIApplication) -> XCUIElement {
        let toggle = app.buttons["Show notes sidebar"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Show notes sidebar button not found"
        )
        tapByCoordinate(toggle)

        let sidebar = app.otherElements["vellum-note-sidebar"]
        XCTAssertTrue(
            sidebar.waitForExistence(timeout: 10),
            "notes sidebar did not appear"
        )
        return sidebar
    }

    private func tapByCoordinate(_ element: XCUIElement) {
        element.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
    }

    private func sortedTitleFields(
        in app: XCUIApplication,
        expectedCount: Int
    ) -> [XCUIElement] {
        let query = app.textFields.matching(
            identifier: "note-screen-title-field"
        )
        XCTAssertTrue(
            waitUntil(timeout: 10) { query.count >= expectedCount },
            "expected \(expectedCount) pane title fields, found \(query.count)"
        )
        return query.allElementsBoundByIndex
            .filter { $0.exists }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private func displayTitle(of titleField: XCUIElement) -> String {
        let value = (titleField.value as? String) ?? titleField.label
        return value.isEmpty ? "Untitled" : value
    }

    private func waitForSidebarRow(
        in sidebar: XCUIElement,
        timeout: TimeInterval = 10,
        matching predicate: (String) -> Bool
    ) -> XCUIElement? {
        var matchingRow: XCUIElement?
        _ = waitUntil(timeout: timeout) {
            matchingRow = sidebar.buttons.allElementsBoundByIndex.first { button in
                button.exists
                    && button.isHittable
                    && button.label != "Close notes"
                    && button.frame.intersects(sidebar.frame)
                    && predicate(button.label)
            }
            return matchingRow != nil
        }
        return matchingRow
    }

    private func matchingButtons(
        labeled label: String,
        in app: XCUIApplication,
        expectedCount: Int
    ) -> [XCUIElement] {
        let query = app.buttons.matching(
            NSPredicate(format: "label == %@", label)
        )
        XCTAssertTrue(
            waitUntil(timeout: 10) { query.count >= expectedCount },
            "expected \(expectedCount) '\(label)' buttons, found \(query.count)"
        )
        return query.allElementsBoundByIndex.filter { $0.exists }
    }

    private func closePanesAddedAbove(
        _ baseline: Int,
        in app: XCUIApplication,
        stateElement: XCUIElement
    ) {
        guard stateElement.exists else { return }

        var state = stateValues(of: stateElement)
        for _ in 0..<4 {
            guard let paneCount = state["panes"].flatMap(Int.init),
                  paneCount > baseline else {
                break
            }

            let closeButtons = app.buttons.matching(
                NSPredicate(format: "label == 'Close pane'")
            ).allElementsBoundByIndex.filter { $0.exists }
            guard let rightmostClose = closeButtons.max(
                by: { $0.frame.minX < $1.frame.minX }
            ) else {
                XCTFail("cleanup found no Close pane button, state: \(state)")
                return
            }

            tapByCoordinate(rightmostClose)
            state = waitForState(stateElement, timeout: 5) {
                ($0["panes"].flatMap(Int.init) ?? paneCount) < paneCount
            }
        }

        XCTAssertEqual(
            state["panes"],
            String(baseline),
            "cleanup did not restore \(baseline) pane: \(state)"
        )
    }

    // MARK: - Synthesized gestures

    private func makeSidebarDragGestureRecord(
        in app: XCUIApplication,
        window: XCUIElement,
        row: XCUIElement,
        dropOffset: CGVector
    ) -> ShapeFlowTestHelpers.GestureRecord? {
        let screenStart = row.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).screenPoint
        let screenEnd = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(
                CGVector(
                    dx: window.frame.width * dropOffset.dx,
                    dy: window.frame.height * dropOffset.dy
                )
            )
            .screenPoint

        let holdInterval: TimeInterval = 0.05
        let movementInterval: TimeInterval = 0.02
        var moves: [(point: CGPoint, offset: TimeInterval)] = []
        var offset: TimeInterval = 0

        for _ in 1...9 {
            offset += holdInterval
            moves.append((point: screenStart, offset: offset))
        }

        let distance = hypot(
            screenEnd.x - screenStart.x,
            screenEnd.y - screenStart.y
        )
        let movementSteps = max(1, Int(ceil(distance / 6)))
        for index in 1...movementSteps {
            let fraction = CGFloat(index) / CGFloat(movementSteps)
            offset += movementInterval
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

        for _ in 1...6 {
            offset += holdInterval
            moves.append((point: screenEnd, offset: offset))
        }

        return ShapeFlowTestHelpers.makeGestureRecord(
            named: "Sidebar note drag",
            gesture: ShapeFlowTestHelpers.PointerGesture(
                start: screenStart,
                moves: moves,
                liftOffset: offset + holdInterval
            ),
            targetProcessID: ShapeFlowTestHelpers.processID(of: app)
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
        let movementSteps = max(1, Int(ceil(distance / 5)))
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
            named: "Slow split divider drag",
            gesture: ShapeFlowTestHelpers.PointerGesture(
                start: screenStart,
                moves: moves,
                liftOffset: offset + sampleInterval
            ),
            targetProcessID: ShapeFlowTestHelpers.processID(of: app)
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

    private func fractions(
        from state: [String: String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Double] {
        guard let encoded = state["fractions"] else {
            XCTFail("split state has no fractions: \(state)", file: file, line: line)
            return []
        }
        let values = encoded.split(separator: ",").compactMap {
            Double($0)
        }
        guard values.count == encoded.split(separator: ",").count else {
            XCTFail(
                "split fractions are malformed: \(encoded)",
                file: file,
                line: line
            )
            return []
        }
        return values
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
