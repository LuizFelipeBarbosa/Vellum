import XCTest

@MainActor
final class SplitPaneFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSplitPanesLaunchArgOpensPanes() {
        let context = launchApp(splitPaneCount: 2)

        let state = waitForState(context.stateElement) { state in
            let grid = self.grid(from: state)
            guard state["panes"] == "2",
                  state["columns"] == "2",
                  grid.count == 2,
                  grid.allSatisfy({
                      abs($0.width - 0.5) <= 0.02
                          && $0.rows.count == 1
                          && abs($0.rows[0] - 1) <= 0.02
                  }),
                  let focused = self.focusedIndex(from: state) else {
                return false
            }
            return (0...1).contains(focused.column) && focused.row == 0
        }
        let grid = grid(from: state)

        XCTAssertEqual(state["panes"], "2", "state: \(state)")
        XCTAssertEqual(state["columns"], "2", "state: \(state)")
        XCTAssertEqual(grid.count, 2, "state: \(state)")
        for column in grid {
            XCTAssertEqual(column.width, 0.5, accuracy: 0.02, "state: \(state)")
            XCTAssertEqual(column.rows.count, 1, "state: \(state)")
            guard let row = column.rows.first else { continue }
            XCTAssertEqual(row, 1, accuracy: 0.02, "state: \(state)")
        }
        guard let focused = focusedIndex(from: state) else {
            return XCTFail("focused pane index is invalid: \(state)")
        }
        XCTAssertTrue((0...1).contains(focused.column), "state: \(state)")
        XCTAssertEqual(focused.row, 0, "state: \(state)")
    }

    func testTapPaneCanvasFocusesThatPane() {
        let context = launchApp(splitPaneCount: 2)
        let initialState = waitForState(context.stateElement) { state in
            guard state["panes"] == "2",
                  state["columns"] == "2",
                  let focused = self.focusedIndex(from: state) else {
                return false
            }
            return (0...1).contains(focused.column) && focused.row == 0
        }
        guard let initialFocused = focusedIndex(from: initialState) else {
            return XCTFail("focused pane index is invalid: \(initialState)")
        }
        let targetColumn = initialFocused.column == 0 ? 1 : 0

        let selectButton = context.app.buttons["Select"]
        guard selectButton.waitForExistence(timeout: 10) else {
            return XCTFail(
                "Select tool button not found, state: "
                    + stateString(of: context.stateElement)
            )
        }
        tapByCoordinate(selectButton)
        XCTAssertTrue(
            waitUntil(timeout: 5) { selectButton.isSelected },
            "Select tool did not become selected, state: "
                + stateString(of: context.stateElement)
        )

        let initialGrid = grid(from: initialState)
        guard initialGrid.count == 2,
              initialGrid.allSatisfy({ $0.rows.count == 1 }),
              initialGrid.indices.contains(targetColumn),
              let containerSize = containerSize(from: initialState) else {
            return XCTFail("two-column grid geometry is invalid: \(initialState)")
        }

        let containerOrigin = context.stateElement.frame.origin
        let targetColumnStartFraction = initialGrid
            .prefix(targetColumn)
            .reduce(0.0) { $0 + $1.width }
        let targetColumnWidthFraction = initialGrid[targetColumn].width
        let targetRowHeightFraction = initialGrid[targetColumn].rows[0]
        let targetPaneFrame = CGRect(
            x: containerOrigin.x
                + CGFloat(targetColumnStartFraction) * containerSize.width,
            y: containerOrigin.y,
            width: CGFloat(targetColumnWidthFraction) * containerSize.width,
            height: CGFloat(targetRowHeightFraction) * containerSize.height
        )

        let closeButtons = matchingButtons(
            labeled: "Close pane",
            in: context.app,
            expectedCount: 2
        )
        let targetPaneTopTrailingCorner = CGPoint(
            x: targetPaneFrame.maxX,
            y: targetPaneFrame.minY
        )
        guard let targetCloseButton = closeButtons.min(by: { first, second in
            hypot(
                first.frame.midX - targetPaneTopTrailingCorner.x,
                first.frame.midY - targetPaneTopTrailingCorner.y
            ) < hypot(
                second.frame.midX - targetPaneTopTrailingCorner.x,
                second.frame.midY - targetPaneTopTrailingCorner.y
            )
        }), targetCloseButton.frame.intersects(targetPaneFrame) else {
            return XCTFail(
                "target pane Close pane button not found, state: \(initialState)"
            )
        }
        let closeButtonExclusion = targetCloseButton.frame.insetBy(
            dx: -24,
            dy: -24
        )

        let toolbarButtons = [
            context.app.buttons["Pen"],
            context.app.buttons["Select"],
            context.app.buttons["Undo"],
            context.app.buttons["Redo"],
        ]
        guard toolbarButtons.allSatisfy({
            $0.waitForExistence(timeout: 5)
        }) else {
            return XCTFail(
                "shared toolbar buttons were not all available, state: "
                    + stateString(of: context.stateElement)
            )
        }
        let toolbarFrame = toolbarButtons.reduce(CGRect.null) {
            $0.union($1.frame)
        }
        let toolbarExclusion = toolbarFrame.insetBy(dx: -24, dy: -24)

        let paneEdgeInset: CGFloat = 40
        let headerExclusionHeight = targetPaneFrame.height * 0.20
        let headerExclusion = CGRect(
            x: targetPaneFrame.minX,
            y: targetPaneFrame.minY,
            width: targetPaneFrame.width,
            height: headerExclusionHeight
        )
        let backlinksRailMinimumWidth: CGFloat = 560
        let backlinksRailMinimumHeight: CGFloat = 500
        let backlinksRailDefensiveWidth: CGFloat = 200
        let shouldAvoidBacklinksRail =
            targetPaneFrame.width >= backlinksRailMinimumWidth
                && targetPaneFrame.height >= backlinksRailMinimumHeight
        let safeMinimumX = targetPaneFrame.minX + paneEdgeInset
        let safeMaximumX = targetPaneFrame.maxX
            - paneEdgeInset
            - (shouldAvoidBacklinksRail ? backlinksRailDefensiveWidth : 0)
        guard safeMaximumX > safeMinimumX else {
            return XCTFail(
                "target pane has no safe horizontal canvas band, state: \(initialState)"
            )
        }

        let centeredCanvasX = min(
            max(targetPaneFrame.midX, safeMinimumX),
            safeMaximumX
        )
        let horizontalCandidates = [
            centeredCanvasX,
            min(
                max(
                    targetPaneFrame.minX + targetPaneFrame.width * 0.38,
                    safeMinimumX
                ),
                safeMaximumX
            ),
            min(
                max(
                    targetPaneFrame.minX + targetPaneFrame.width * 0.62,
                    safeMinimumX
                ),
                safeMaximumX
            ),
        ]
        let verticalCandidates: [CGFloat] = [0.62, 0.55, 0.72, 0.45].map {
            targetPaneFrame.minY + targetPaneFrame.height * $0
        }
        let canvasInterior = targetPaneFrame.insetBy(
            dx: paneEdgeInset,
            dy: paneEdgeInset
        )
        let tapCandidates = verticalCandidates.flatMap { y in
            horizontalCandidates.map { x in CGPoint(x: x, y: y) }
        }
        guard let tapPoint = tapCandidates.first(where: { point in
            canvasInterior.contains(point)
                && point.x <= safeMaximumX
                && !headerExclusion.contains(point)
                && !closeButtonExclusion.contains(point)
                && !toolbarExclusion.contains(point)
        }) else {
            return XCTFail(
                "no safe canvas tap point cleared the pane chrome and toolbar; "
                    + "pane: \(targetPaneFrame), close: \(closeButtonExclusion), "
                    + "toolbar: \(toolbarExclusion), state: \(initialState)"
            )
        }

        context.window.coordinate(withNormalizedOffset: .zero)
            .withOffset(
                CGVector(
                    dx: tapPoint.x - context.window.frame.minX,
                    dy: tapPoint.y - context.window.frame.minY
                )
            )
            .tap()

        let focusedState = waitForState(context.stateElement) { state in
            guard state["panes"] == "2",
                  state["columns"] == "2",
                  let focused = self.focusedIndex(from: state) else {
                return false
            }
            return focused.column == targetColumn && focused.row == 0
        }
        guard let focused = focusedIndex(from: focusedState) else {
            return XCTFail("focused pane index is invalid: \(focusedState)")
        }
        XCTAssertEqual(focused.column, targetColumn, "state: \(focusedState)")
        XCTAssertEqual(focused.row, 0, "state: \(focusedState)")
        XCTAssertEqual(focusedState["panes"], "2", "state: \(focusedState)")
        XCTAssertEqual(focusedState["columns"], "2", "state: \(focusedState)")
    }

    func testSidebarDragCreatesPane() {
        let context = launchApp(splitPaneCount: 1)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "1" && $0["columns"] == "1"
        }
        XCTAssertEqual(initialState["panes"], "1", "state: \(initialState)")
        XCTAssertEqual(initialState["columns"], "1", "state: \(initialState)")

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
            $0["panes"] == "2"
                && $0["columns"] == "2"
                && $0["dragging"] == "0"
        }
        XCTAssertEqual(createdState["panes"], "2", "state: \(createdState)")
        XCTAssertEqual(createdState["columns"], "2", "state: \(createdState)")

        closePanesAddedAbove(
            1,
            in: context.app,
            stateElement: context.stateElement
        )
    }

    func testDragAlreadyOpenNoteFocusesPane() {
        let context = launchApp(splitPaneCount: 2)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "2"
                && $0["columns"] == "2"
                && self.focusedIndex(from: $0) != nil
        }
        guard let initialFocused = focusedIndex(from: initialState) else {
            return XCTFail("initial focused pane index is invalid: \(initialState)")
        }
        XCTAssertTrue((0...1).contains(initialFocused.column), "state: \(initialState)")
        XCTAssertEqual(initialFocused.row, 0, "state: \(initialState)")

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
            guard $0["panes"] == "2",
                  $0["columns"] == "2",
                  $0["dragging"] == "0",
                  let focused = self.focusedIndex(from: $0) else {
                return false
            }
            return focused.column == 0 && focused.row == 0
        }
        XCTAssertEqual(focusedState["panes"], "2", "state: \(focusedState)")
        XCTAssertEqual(focusedState["columns"], "2", "state: \(focusedState)")
        guard let focused = focusedIndex(from: focusedState) else {
            return XCTFail("final focused pane index is invalid: \(focusedState)")
        }
        XCTAssertEqual(
            focused.column,
            0,
            "initial focus was \(initialFocused), final state: \(focusedState)"
        )
        XCTAssertEqual(focused.row, 0, "state: \(focusedState)")
    }

    func testClosePaneRenormalizesFractions() {
        let context = launchApp(splitPaneCount: 3)
        let initialState = waitForState(context.stateElement) {
            ($0["panes"].flatMap(Int.init) ?? 0) >= 3
        }
        guard let paneCount = initialState["panes"].flatMap(Int.init) else {
            return XCTFail("pane count is invalid: \(initialState)")
        }
        if paneCount < 3 {
            XCTFail(
                "fewer than 3 panes available: \(stateString(of: context.stateElement))"
            )
            return
        }

        let closeButtons = matchingButtons(
            labeled: "Close pane",
            in: context.app,
            expectedCount: 3
        )
        guard let bottomRightmostClose = closeButtons.max(
            by: { first, second in
                first.frame.minX != second.frame.minX
                    ? first.frame.minX < second.frame.minX
                    : first.frame.minY < second.frame.minY
            }
        ) else {
            return XCTFail("no Close pane button found")
        }
        tapByCoordinate(bottomRightmostClose)

        let closedState = waitForState(context.stateElement) {
            $0["panes"] == "2"
        }
        let grid = grid(from: closedState)
        XCTAssertEqual(closedState["panes"], "2", "state: \(closedState)")
        XCTAssertEqual(closedState["columns"], "2", "state: \(closedState)")
        XCTAssertEqual(grid.count, 2, "state: \(closedState)")
        XCTAssertEqual(grid.map(\.width).reduce(0, +), 1.0, accuracy: 0.02)

        let minimumFraction = 320 / Double(context.window.frame.width)
        for column in grid {
            XCTAssertGreaterThanOrEqual(
                column.width,
                minimumFraction - 0.02,
                "width \(column.width) violates the 320pt minimum, state: \(closedState)"
            )
        }
    }

    func testDividerDragResizesAndClamps() {
        let context = launchApp(splitPaneCount: 2)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "2"
                && $0["columns"] == "2"
                && self.grid(from: $0).count == 2
        }
        let initialWidths = grid(from: initialState).map(\.width)
        guard initialWidths.count == 2 else {
            return XCTFail("initial grid widths are invalid: \(initialState)")
        }

        let windowWidth = Double(context.window.frame.width)
        let dividerY = context.window.frame.height * 0.60
        let initialPaneZeroWidth = initialWidths[0] * windowWidth
        let targetPaneZeroWidth = min(
            initialPaneZeroWidth + 200,
            windowWidth - 320
        )
        let maximumPhaseAAttempts = 20
        var phaseAAttempts = 0
        var phaseAState = initialState

        while phaseAAttempts < maximumPhaseAAttempts {
            let currentWidths = grid(from: phaseAState).map(\.width)
            guard currentWidths.count == 2 else {
                return XCTFail("current grid widths are invalid: \(phaseAState)")
            }

            let currentPaneZeroWidth = currentWidths[0] * windowWidth
            let remaining = targetPaneZeroWidth - currentPaneZeroWidth
            if abs(remaining) <= 5 {
                break
            }

            phaseAAttempts += 1
            let chunkDistance = max(-30.0, min(30.0, remaining))
            let dividerX = currentWidths[0] * windowWidth
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

            let previousGrid = phaseAState["grid"]
            phaseAState = waitForState(context.stateElement, timeout: 3) {
                $0["panes"] == "2" && $0["grid"] != previousGrid
            }
        }

        let resizedWidths = grid(from: phaseAState).map(\.width)
        guard resizedWidths.count == 2 else {
            return XCTFail("resized grid widths are invalid: \(phaseAState)")
        }
        let resizedPaneZeroWidth = resizedWidths[0] * windowWidth
        let paneZeroIncrease = resizedPaneZeroWidth - initialPaneZeroWidth
        XCTAssertGreaterThan(
            resizedWidths[0],
            initialWidths[0],
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
        var minimumObservedFractionOne = resizedWidths[1]

        while phaseBAttempts < maximumPhaseBAttempts,
              requestedPhaseBDistance < 2_000,
              unchangedPolls < 2 {
            let currentWidths = grid(from: phaseBState).map(\.width)
            guard currentWidths.count == 2 else {
                return XCTFail("phase B grid widths are invalid: \(phaseBState)")
            }

            let chunkDistance = min(30.0, 2_000 - requestedPhaseBDistance)
            let dividerX = currentWidths[0] * windowWidth
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

            let previousGrid = phaseBState["grid"]
            let polledState = waitForState(context.stateElement, timeout: 1.5) {
                $0["panes"] == "2" && $0["grid"] != previousGrid
            }
            let polledWidths = grid(from: polledState).map(\.width)
            guard polledWidths.count == 2 else {
                return XCTFail("polled phase B grid widths are invalid: \(polledState)")
            }

            minimumObservedFractionOne = min(
                minimumObservedFractionOne,
                polledWidths[1]
            )
            if polledWidths[1] == currentWidths[1] {
                unchangedPolls += 1
            } else {
                unchangedPolls = 0
            }
            phaseBState = polledState
        }

        let finalWidths = grid(from: phaseBState).map(\.width)
        guard finalWidths.count == 2 else {
            return XCTFail("final grid widths are invalid: \(phaseBState)")
        }
        XCTAssertEqual(
            finalWidths[1],
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

    func testTapSidebarRowFocusesOpenNote() {
        let context = launchApp(splitPaneCount: 2)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "2" && $0["columns"] == "2"
        }
        XCTAssertEqual(initialState["panes"], "2", "state: \(initialState)")
        XCTAssertEqual(initialState["columns"], "2", "state: \(initialState)")

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
            guard $0["panes"] == "2",
                  $0["columns"] == "2",
                  let focused = self.focusedIndex(from: $0) else {
                return false
            }
            return focused.column == 1 && focused.row == 0
        }
        guard let focused = focusedIndex(from: focusedState) else {
            return XCTFail("focused pane index is invalid: \(focusedState)")
        }
        XCTAssertEqual(focused.column, 1, "state: \(focusedState)")
        XCTAssertEqual(focused.row, 0, "state: \(focusedState)")
        XCTAssertEqual(focusedState["panes"], "2", "state: \(focusedState)")
        XCTAssertEqual(focusedState["columns"], "2", "state: \(focusedState)")
        XCTAssertTrue(
            sidebar.exists,
            "sidebar closed after tapping an already-open note row"
        )
    }

    func testTapSidebarRowReplacesFocusedPane() throws {
        let context = launchApp(splitPaneCount: 2)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "2"
                && $0["columns"] == "2"
                && self.focusedIndex(from: $0) != nil
        }
        guard let focused = focusedIndex(from: initialState) else {
            return XCTFail("initial focused pane index is invalid: \(initialState)")
        }

        let initialGrid = grid(from: initialState)
        guard initialGrid.indices.contains(focused.column),
              initialGrid[focused.column].rows.indices.contains(focused.row) else {
            return XCTFail(
                "focused pane is outside the decoded grid: \(initialState)"
            )
        }

        let titleFields = sortedTitleFields(in: context.app, expectedCount: 2)
        guard titleFields.count >= 2 else {
            return XCTFail("two pane title fields were not found")
        }
        let openTitles = titleFields.prefix(2).map(displayTitle)
        let focusedTitleFieldIndex = initialGrid
            .prefix(focused.column)
            .reduce(0) { $0 + $1.rows.count } + focused.row
        guard titleFields.indices.contains(focusedTitleFieldIndex) else {
            return XCTFail(
                "focused title field is outside the decoded grid: \(initialState)"
            )
        }
        let originalFocusedTitle = displayTitle(
            of: titleFields[focusedTitleFieldIndex]
        )

        let sidebar = showSidebar(in: context.app)
        let sidebarButtons = sidebar.buttons
        let hasDifferentSidebarRow = waitUntil(timeout: 10) {
            sidebarButtons.allElementsBoundByIndex.contains { button in
                button.exists
                    && button.label != "Close notes"
                    && button.label != openTitles[0]
                    && button.label != openTitles[1]
            }
        }
        guard hasDifferentSidebarRow else {
            return XCTFail(
                "no sidebar row exists that differs from both open pane titles, "
                    + "state: \(stateString(of: context.stateElement))"
            )
        }
        guard let row = waitForSidebarRow(in: sidebar, matching: { label in
            label != openTitles[0] && label != openTitles[1]
        }) else {
            throw XCTSkip(
                "no sidebar row found that differs from both open pane titles"
            )
        }
        let replacementTitle = row.label
        tapByCoordinate(row)

        let unchangedState = waitForState(context.stateElement) {
            $0["panes"] == "2" && $0["columns"] == "2"
        }
        XCTAssertEqual(unchangedState["panes"], "2", "state: \(unchangedState)")
        XCTAssertEqual(unchangedState["columns"], "2", "state: \(unchangedState)")

        let replacedTitleFields = sortedTitleFields(
            in: context.app,
            expectedCount: 2
        )
        guard replacedTitleFields.indices.contains(focusedTitleFieldIndex) else {
            return XCTFail(
                "focused title field disappeared after replacement, state: \(unchangedState)"
            )
        }
        let replacedTitleField = replacedTitleFields[focusedTitleFieldIndex]
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.displayTitle(of: replacedTitleField) == replacementTitle
            },
            "focused pane '\(originalFocusedTitle)' did not become "
                + "'\(replacementTitle)', state: "
                + stateString(of: context.stateElement)
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) { !sidebar.exists },
            "sidebar remained open after replacing the focused pane"
        )
        XCTAssertFalse(sidebar.exists)
    }

    func testSidebarDragToBottomEdgeStacksPane() {
        let context = launchApp(splitPaneCount: 1)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "1" && $0["columns"] == "1"
        }
        XCTAssertEqual(initialState["panes"], "1", "state: \(initialState)")
        XCTAssertEqual(initialState["columns"], "1", "state: \(initialState)")

        addTeardownBlock { @MainActor in
            self.closePanesAddedAbove(
                1,
                in: context.app,
                stateElement: context.stateElement
            )
        }

        let titleFields = sortedTitleFields(in: context.app, expectedCount: 1)
        guard let titleField = titleFields.first else {
            return XCTFail("single pane title field not found")
        }
        let openTitle = displayTitle(of: titleField)

        let sidebar = showSidebar(in: context.app)
        guard let row = waitForSidebarRow(in: sidebar, matching: { label in
            label != openTitle
        }) else {
            return XCTFail(
                "no visible sidebar row differed from '\(openTitle)'"
            )
        }
        guard let record = makeSidebarDragGestureRecord(
            in: context.app,
            window: context.window,
            row: row,
            dropOffset: CGVector(dx: 0.50, dy: 0.90)
        ) else {
            return XCTFail("XCTest synthesized pointer support is unavailable.")
        }

        let gestureFinished = XCTestExpectation(
            description: "bottom-edge sidebar drag finished"
        )
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertTrue(
                ShapeFlowTestHelpers.synthesize(record),
                "failed to synthesize the bottom-edge sidebar note drag"
            )
            gestureFinished.fulfill()
        }

        let midDragDeadline = Date().addingTimeInterval(5)
        var sawExpectedTarget = false
        while Date() < midDragDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let state = stateValues(of: context.stateElement)
            if state["target"] == "row-0.1" {
                sawExpectedTarget = true
            }
            if state["dragging"] == "0" && sawExpectedTarget {
                break
            }
        }

        wait(for: [gestureFinished], timeout: 15)
        XCTContext.runActivity(
            named: "Observed row-0.1 target mid-drag: \(sawExpectedTarget)"
        ) { _ in }

        let settledState = waitForState(context.stateElement, timeout: 5) {
            $0["dragging"] == "0"
        }
        XCTAssertEqual(settledState["dragging"], "0", "state: \(settledState)")

        let stackedState = waitForState(context.stateElement) {
            $0["panes"] == "2"
                && $0["columns"] == "1"
                && $0["dragging"] == "0"
        }
        let stackedGrid = grid(from: stackedState)
        XCTAssertEqual(stackedState["panes"], "2", "state: \(stackedState)")
        XCTAssertEqual(stackedState["columns"], "1", "state: \(stackedState)")
        XCTAssertEqual(stackedGrid.count, 1, "state: \(stackedState)")
        guard let rows = stackedGrid.first?.rows else {
            return XCTFail("stacked column is missing: \(stackedState)")
        }
        XCTAssertEqual(rows.count, 2, "state: \(stackedState)")
        for row in rows {
            XCTAssertEqual(row, 0.5, accuracy: 0.05, "state: \(stackedState)")
        }

        closePanesAddedAbove(
            1,
            in: context.app,
            stateElement: context.stateElement
        )
    }

    func testRowDividerDragResizesAndClamps() {
        let context = launchApp(gridRows: [2])
        let initialState = waitForState(context.stateElement) {
            let grid = self.grid(from: $0)
            return $0["panes"] == "2"
                && $0["columns"] == "1"
                && grid.count == 1
                && grid[0].rows.count == 2
        }
        let initialGrid = grid(from: initialState)
        guard initialGrid.count == 1, initialGrid[0].rows.count == 2 else {
            return XCTFail("initial row grid is invalid: \(initialState)")
        }
        let initialRows = initialGrid[0].rows

        guard let containerSize = containerSize(from: initialState) else {
            return
        }
        let containerOrigin = context.stateElement.frame.origin
        let containerHeight = Double(containerSize.height)
        let containerWidth = Double(containerSize.width)
        let initialRowZeroHeight = initialRows[0] * containerHeight
        let targetRowZeroHeight = min(
            initialRowZeroHeight + 150,
            containerHeight - 280
        )
        let maximumPhaseAAttempts = 20
        var phaseAAttempts = 0
        var phaseAState = initialState

        while phaseAAttempts < maximumPhaseAAttempts {
            let currentGrid = grid(from: phaseAState)
            guard currentGrid.count == 1,
                  currentGrid[0].rows.count == 2 else {
                return XCTFail("current row grid is invalid: \(phaseAState)")
            }
            let currentRows = currentGrid[0].rows
            let currentRowZeroHeight = currentRows[0] * containerHeight
            let remaining = targetRowZeroHeight - currentRowZeroHeight
            if abs(remaining) <= 5 {
                break
            }

            phaseAAttempts += 1
            let chunkDistance = max(-30.0, min(30.0, remaining))
            let columnCenterX = currentGrid[0].width * containerWidth / 2
            let dividerY = currentRows[0] * containerHeight
            guard let record = makeSlowDividerDragGestureRecord(
                in: context.app,
                window: context.window,
                from: CGPoint(
                    x: containerOrigin.x + CGFloat(columnCenterX),
                    y: containerOrigin.y + CGFloat(dividerY)
                ),
                to: CGPoint(
                    x: containerOrigin.x + CGFloat(columnCenterX),
                    y: containerOrigin.y + CGFloat(dividerY + chunkDistance)
                )
            ) else {
                return XCTFail("XCTest synthesized pointer support is unavailable.")
            }

            XCTAssertTrue(
                ShapeFlowTestHelpers.synthesize(record),
                "failed to synthesize phase A row divider drag \(phaseAAttempts)"
            )

            let previousGrid = phaseAState["grid"]
            phaseAState = waitForState(context.stateElement, timeout: 3) {
                $0["columns"] == "1" && $0["grid"] != previousGrid
            }
        }

        let resizedGrid = grid(from: phaseAState)
        guard resizedGrid.count == 1, resizedGrid[0].rows.count == 2 else {
            return XCTFail("resized row grid is invalid: \(phaseAState)")
        }
        let resizedRows = resizedGrid[0].rows
        let resizedRowZeroHeight = resizedRows[0] * containerHeight
        let rowZeroIncrease = resizedRowZeroHeight - initialRowZeroHeight
        XCTAssertGreaterThan(
            resizedRows[0],
            initialRows[0],
            "row 0 did not grow, state: \(phaseAState)"
        )
        XCTAssertGreaterThanOrEqual(
            rowZeroIncrease,
            80,
            "row 0 grew only \(rowZeroIncrease)pt, state: \(phaseAState)"
        )
        XCTAssertLessThanOrEqual(
            rowZeroIncrease,
            250,
            "row 0 grew \(rowZeroIncrease)pt, state: \(phaseAState)"
        )

        let minimumFraction = 280 / containerHeight
        let maximumPhaseBAttempts = 75
        var phaseBAttempts = 0
        var requestedPhaseBDistance = 0.0
        var unchangedPolls = 0
        var phaseBState = phaseAState
        var minimumObservedRowOne = resizedRows[1]

        while phaseBAttempts < maximumPhaseBAttempts,
              requestedPhaseBDistance < 2_000,
              unchangedPolls < 2 {
            let currentGrid = grid(from: phaseBState)
            guard currentGrid.count == 1,
                  currentGrid[0].rows.count == 2 else {
                return XCTFail("phase B row grid is invalid: \(phaseBState)")
            }
            let currentRows = currentGrid[0].rows
            let chunkDistance = min(30.0, 2_000 - requestedPhaseBDistance)
            let columnCenterX = currentGrid[0].width * containerWidth / 2
            let dividerY = currentRows[0] * containerHeight
            phaseBAttempts += 1
            requestedPhaseBDistance += chunkDistance

            guard let record = makeSlowDividerDragGestureRecord(
                in: context.app,
                window: context.window,
                from: CGPoint(
                    x: containerOrigin.x + CGFloat(columnCenterX),
                    y: containerOrigin.y + CGFloat(dividerY)
                ),
                to: CGPoint(
                    x: containerOrigin.x + CGFloat(columnCenterX),
                    y: containerOrigin.y + CGFloat(dividerY + chunkDistance)
                )
            ) else {
                return XCTFail("XCTest synthesized pointer support is unavailable.")
            }

            XCTAssertTrue(
                ShapeFlowTestHelpers.synthesize(record),
                "failed to synthesize phase B row divider drag \(phaseBAttempts)"
            )

            let previousGrid = phaseBState["grid"]
            let polledState = waitForState(
                context.stateElement,
                timeout: 1.5
            ) {
                $0["columns"] == "1" && $0["grid"] != previousGrid
            }
            let polledGrid = grid(from: polledState)
            guard polledGrid.count == 1,
                  polledGrid[0].rows.count == 2 else {
                return XCTFail(
                    "polled phase B row grid is invalid: \(polledState)"
                )
            }
            let polledRows = polledGrid[0].rows
            minimumObservedRowOne = min(
                minimumObservedRowOne,
                polledRows[1]
            )
            if polledRows[1] == currentRows[1] {
                unchangedPolls += 1
            } else {
                unchangedPolls = 0
            }
            phaseBState = polledState
        }

        let finalGrid = grid(from: phaseBState)
        guard finalGrid.count == 1, finalGrid[0].rows.count == 2 else {
            return XCTFail("final row grid is invalid: \(phaseBState)")
        }
        XCTAssertEqual(
            finalGrid[0].rows[1],
            minimumFraction,
            accuracy: 0.02,
            "bottom row did not settle at the 280pt clamp, state: \(phaseBState)"
        )
        XCTAssertGreaterThanOrEqual(
            minimumObservedRowOne,
            minimumFraction - 0.01,
            "bottom row moved below the clamp, state: \(phaseBState)"
        )
    }

    func testInteriorDropReplacesPaneNote() throws {
        let context = launchApp(splitPaneCount: 2)
        let initialState = waitForState(context.stateElement) {
            $0["panes"] == "2"
                && $0["columns"] == "2"
                && self.grid(from: $0).count == 2
        }
        let widths = grid(from: initialState).map(\.width)
        guard widths.count == 2 else {
            return XCTFail("initial grid widths are invalid: \(initialState)")
        }

        let windowWidth = Double(context.window.frame.width)
        let paneOneStartXFraction = widths[0]
        let paneOneInteriorXFraction =
            paneOneStartXFraction + widths[1] / 2
        let paneOneInteriorX = paneOneInteriorXFraction * windowWidth
        guard paneOneInteriorX > 0, paneOneInteriorX < windowWidth else {
            return XCTFail(
                "pane 1 interior x is outside the window: \(initialState)"
            )
        }

        let titleFields = sortedTitleFields(in: context.app, expectedCount: 2)
        guard titleFields.count >= 2 else {
            return XCTFail("two pane title fields were not found")
        }
        let openTitles = titleFields.prefix(2).map(displayTitle)

        let sidebar = showSidebar(in: context.app)
        guard let row = waitForSidebarRow(in: sidebar, matching: { label in
            label != openTitles[0] && label != openTitles[1]
        }) else {
            throw XCTSkip(
                "no sidebar row found that differs from both open pane titles"
            )
        }
        let replacementTitle = row.label
        guard let record = makeSidebarDragGestureRecord(
            in: context.app,
            window: context.window,
            row: row,
            dropOffset: CGVector(
                dx: CGFloat(paneOneInteriorXFraction),
                dy: 0.50
            )
        ) else {
            return XCTFail("XCTest synthesized pointer support is unavailable.")
        }

        XCTAssertTrue(
            ShapeFlowTestHelpers.synthesize(record),
            "failed to synthesize the pane-interior sidebar note drag"
        )

        let settledState = waitForState(context.stateElement, timeout: 5) {
            $0["dragging"] == "0"
        }
        XCTAssertEqual(settledState["dragging"], "0", "state: \(settledState)")

        let replacedState = waitForState(context.stateElement) {
            $0["panes"] == "2"
                && $0["columns"] == "2"
                && $0["dragging"] == "0"
        }
        XCTAssertEqual(replacedState["panes"], "2", "state: \(replacedState)")
        XCTAssertEqual(replacedState["columns"], "2", "state: \(replacedState)")
        XCTAssertTrue(
            waitUntil(timeout: 5) { !sidebar.exists },
            "sidebar remained open after replacing pane 1"
        )
        XCTAssertFalse(sidebar.exists)

        let replacedTitleFields = sortedTitleFields(
            in: context.app,
            expectedCount: 2
        )
        guard replacedTitleFields.indices.contains(1) else {
            return XCTFail(
                "pane 1 title field disappeared after replacement, state: \(replacedState)"
            )
        }
        let paneOneTitleField = replacedTitleFields[1]
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.displayTitle(of: paneOneTitleField) == replacementTitle
            },
            "pane 1 title did not become '\(replacementTitle)', state: "
                + stateString(of: context.stateElement)
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

    private func launchApp(
        gridRows: [Int]
    ) -> (
        app: XCUIApplication,
        window: XCUIElement,
        stateElement: XCUIElement
    ) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-vellum-split-grid",
            gridRows.map(String.init).joined(separator: ","),
        ]
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
            .sorted { first, second in
                first.frame.minX != second.frame.minX
                    ? first.frame.minX < second.frame.minX
                    : first.frame.minY < second.frame.minY
            }
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
            guard let bottomRightmostClose = closeButtons.max(
                by: { first, second in
                    first.frame.minX != second.frame.minX
                        ? first.frame.minX < second.frame.minX
                        : first.frame.minY < second.frame.minY
                }
            ) else {
                XCTFail("cleanup found no Close pane button, state: \(state)")
                return
            }

            tapByCoordinate(bottomRightmostClose)
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

    private func grid(
        from state: [String: String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [(width: Double, rows: [Double])] {
        guard let encoded = state["grid"] else {
            XCTFail("split state has no grid: \(state)", file: file, line: line)
            return []
        }

        var columns: [(width: Double, rows: [Double])] = []
        let tokens = encoded.split(
            separator: "|",
            omittingEmptySubsequences: false
        )
        for tokenSubstring in tokens {
            let token = String(tokenSubstring)
            guard let openingBracket = token.firstIndex(of: "["),
                  token.last == "]",
                  openingBracket != token.startIndex else {
                XCTFail(
                    "split grid token is malformed: '\(token)', "
                        + "grid: '\(encoded)', state: \(state)",
                    file: file,
                    line: line
                )
                return []
            }

            let widthSubstring = token[..<openingBracket]
            let rowsStart = token.index(after: openingBracket)
            let rowsEnd = token.index(before: token.endIndex)
            let rowSubstrings = token[rowsStart..<rowsEnd].split(
                separator: ",",
                omittingEmptySubsequences: false
            )
            guard let width = Double(widthSubstring),
                  !rowSubstrings.isEmpty else {
                XCTFail(
                    "split grid token is malformed: '\(token)', "
                        + "grid: '\(encoded)', state: \(state)",
                    file: file,
                    line: line
                )
                return []
            }

            let rows = rowSubstrings.compactMap(Double.init)
            guard rows.count == rowSubstrings.count else {
                XCTFail(
                    "split grid token is malformed: '\(token)', "
                        + "grid: '\(encoded)', state: \(state)",
                    file: file,
                    line: line
                )
                return []
            }
            columns.append((width: width, rows: rows))
        }
        return columns
    }

    private func containerSize(
        from state: [String: String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGSize? {
        guard let encoded = state["size"] else {
            XCTFail("split state has no size: \(state)", file: file, line: line)
            return nil
        }
        let components = encoded.split(separator: "x", omittingEmptySubsequences: false)
        guard components.count == 2,
              let width = Double(components[0]),
              let height = Double(components[1]) else {
            XCTFail("split state size is malformed: '\(encoded)', state: \(state)", file: file, line: line)
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private func focusedIndex(
        from state: [String: String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (column: Int, row: Int)? {
        guard let encoded = state["focused"] else {
            XCTFail(
                "split state has no focused index: \(state)",
                file: file,
                line: line
            )
            return nil
        }
        guard encoded != "-1" else { return nil }

        let components = encoded.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard components.count == 2,
              let column = Int(components[0]),
              let row = Int(components[1]) else {
            XCTFail(
                "split focused index is malformed: '\(encoded)', state: \(state)",
                file: file,
                line: line
            )
            return nil
        }
        return (column: column, row: row)
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
