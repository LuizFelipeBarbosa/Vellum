import XCTest

@MainActor
final class ShapeSnapFlowUITests: XCTestCase {
    /// The region every test draws in, cleared before each run so leftover ink from an earlier
    /// test cannot sit under the stroke and perturb recognition.
    private static let drawingAreaStart = CGVector(dx: 0.22, dy: 0.36)
    private static let drawingAreaEnd = CGVector(dx: 0.74, dy: 0.63)

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHeldPenStrokeSnapsToOneShape() {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        clearShapeDrawingArea(in: app, window: window)
        selectPen(in: app)

        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = ShapeFlowTestHelpers.shapeCount(of: shapeCountElement)

        let startCoordinate = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.28, dy: 0.42)
        )
        let endCoordinate = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.60, dy: 0.42)
        )
        startCoordinate.press(
            forDuration: 0.05,
            thenDragTo: endCoordinate,
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )

        let expectedShapeCount = shapeCountBefore + 1
        let snapped = expectation(
            for: NSPredicate(
                format: "value == %@",
                String(expectedShapeCount)
            ),
            evaluatedWith: shapeCountElement
        )
        wait(for: [snapped], timeout: 5)
        XCTAssertEqual(
            ShapeFlowTestHelpers.shapeCount(of: shapeCountElement),
            expectedShapeCount
        )
    }

    func testHeldLineCanBeAdjustedBeforeLiftAndUndoneOnce() {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        clearShapeDrawingArea(in: app, window: window)
        selectPen(in: app)

        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = ShapeFlowTestHelpers.shapeCount(of: shapeCountElement)

        let startCoordinate = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.28, dy: 0.42)
        )
        let dwellCoordinate = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.52, dy: 0.42)
        )
        let adjustedCoordinate = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.68, dy: 0.56)
        )
        performHeldLineAdjustment(
            in: app,
            from: startCoordinate.screenPoint,
            through: dwellCoordinate.screenPoint,
            to: adjustedCoordinate.screenPoint
        )

        let expectedShapeCount = shapeCountBefore + 1
        let snapped = expectation(
            for: NSPredicate(
                format: "value == %@",
                String(expectedShapeCount)
            ),
            evaluatedWith: shapeCountElement
        )
        wait(for: [snapped], timeout: 5)

        ShapeFlowTestHelpers.selectTool("Select", in: app)
        ShapeFlowTestHelpers.selectTool("Box", in: app)
        let selectionStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.24, dy: 0.38)
        )
        let selectionEnd = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.72, dy: 0.61)
        )
        selectionStart.press(forDuration: 0.05, thenDragTo: selectionEnd)

        let vertexHandles = app.otherElements["vellum-shape-vertex-handles"]
        XCTAssertTrue(
            vertexHandles.waitForExistence(timeout: 5),
            "adjusted line vertex handles did not appear"
        )
        let vertices = ShapeFlowTestHelpers.vertices(
            from: ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        )
        XCTAssertEqual(vertices.count, 2)
        guard vertices.count == 2 else { return }
        XCTAssertGreaterThan(
            abs(vertices[1].y - vertices[0].y),
            40,
            "the final line still reflects the pre-hold horizontal stroke"
        )

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "undo button not found")
        undo.tap()

        let undone = expectation(
            for: NSPredicate(
                format: "value == %@",
                String(shapeCountBefore)
            ),
            evaluatedWith: shapeCountElement
        )
        wait(for: [undone], timeout: 5)
        XCTAssertEqual(
            ShapeFlowTestHelpers.shapeCount(of: shapeCountElement),
            shapeCountBefore
        )
    }

    func testHeldLineSnapsToOneShapeAndUndoesOnce() {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        clearShapeDrawingArea(in: app, window: window)
        selectPen(in: app)

        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = ShapeFlowTestHelpers.shapeCount(of: shapeCountElement)

        let startCoordinate = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.28, dy: 0.42)
        )
        let endCoordinate = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.60, dy: 0.42)
        )
        startCoordinate.press(
            forDuration: 0.05,
            thenDragTo: endCoordinate,
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )

        let expectedShapeCount = shapeCountBefore + 1
        let snapped = expectation(
            for: NSPredicate(
                format: "value == %@",
                String(expectedShapeCount)
            ),
            evaluatedWith: shapeCountElement
        )
        wait(for: [snapped], timeout: 5)
        XCTAssertEqual(
            ShapeFlowTestHelpers.shapeCount(of: shapeCountElement),
            expectedShapeCount
        )

        ShapeFlowTestHelpers.selectTool("Select", in: app)
        ShapeFlowTestHelpers.selectTool("Box", in: app)
        let selectionStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.24, dy: 0.38)
        )
        let selectionEnd = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.72, dy: 0.61)
        )
        selectionStart.press(forDuration: 0.05, thenDragTo: selectionEnd)

        let vertexHandles = app.otherElements["vellum-shape-vertex-handles"]
        XCTAssertTrue(
            vertexHandles.waitForExistence(timeout: 5),
            "snapped line vertex handles did not appear"
        )
        let vertices = ShapeFlowTestHelpers.vertices(
            from: ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        )
        XCTAssertEqual(vertices.count, 2)
        guard vertices.count == 2 else { return }
        let horizontalDelta = abs(vertices[1].x - vertices[0].x)
        let verticalDelta = abs(vertices[1].y - vertices[0].y)
        XCTAssertGreaterThan(
            hypot(horizontalDelta, verticalDelta),
            100,
            "snapped line does not have meaningful extent"
        )
        XCTAssertLessThan(
            verticalDelta,
            40,
            "snapped line is not roughly horizontal"
        )

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "undo button not found")
        undo.tap()

        let undone = expectation(
            for: NSPredicate(
                format: "value == %@",
                String(shapeCountBefore)
            ),
            evaluatedWith: shapeCountElement
        )
        wait(for: [undone], timeout: 5)
        XCTAssertEqual(
            ShapeFlowTestHelpers.shapeCount(of: shapeCountElement),
            shapeCountBefore
        )
    }

    private func clearShapeDrawingArea(in app: XCUIApplication, window: XCUIElement) {
        ShapeFlowTestHelpers.clearShapeDrawingArea(
            in: app,
            window: window,
            selectionStart: Self.drawingAreaStart,
            selectionEnd: Self.drawingAreaEnd
        )
    }

    /// Leaves the pen active. Selecting another tool first guarantees the pen tap is a real
    /// switch rather than a no-op on an already-selected tool.
    private func selectPen(in app: XCUIApplication) {
        ShapeFlowTestHelpers.selectTool("Select", in: app)
        ShapeFlowTestHelpers.selectTool("Pen", in: app)

        let penSelected = expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: app.buttons["Pen"]
        )
        wait(for: [penSelected], timeout: 5)
    }

    /// Strokes towards `dwellPoint`, holds there long enough for the line to snap, then drags the
    /// snapped endpoint to `adjustedPoint` before lifting — three phases in one continuous touch,
    /// which `press(thenDragTo:)` cannot express.
    private func performHeldLineAdjustment(
        in app: XCUIApplication,
        from start: CGPoint,
        through dwellPoint: CGPoint,
        to adjustedPoint: CGPoint
    ) {
        var moves: [(point: CGPoint, offset: TimeInterval)] = []

        let initialMoveCount = 10
        let initialMoveInterval: TimeInterval = 0.03
        for index in 1...initialMoveCount {
            moves.append(
                (
                    point: interpolate(
                        from: start,
                        to: dwellPoint,
                        fraction: CGFloat(index) / CGFloat(initialMoveCount)
                    ),
                    offset: TimeInterval(index) * initialMoveInterval
                )
            )
        }

        // Repeating the exact point prevents XCTest from interpolating movement
        // across what should be the stationary portion of the gesture.
        let holdSampleInterval: TimeInterval = 0.05
        let holdSampleCount = 18
        let holdStartOffset = TimeInterval(initialMoveCount) * initialMoveInterval
        for index in 1...holdSampleCount {
            moves.append(
                (
                    point: dwellPoint,
                    offset: holdStartOffset + TimeInterval(index) * holdSampleInterval
                )
            )
        }

        let adjustmentStartOffset =
            holdStartOffset + TimeInterval(holdSampleCount + 1) * holdSampleInterval
        let adjustmentMoveCount = 8
        let adjustmentInterval: TimeInterval = 0.04
        for index in 1...adjustmentMoveCount {
            moves.append(
                (
                    point: interpolate(
                        from: dwellPoint,
                        to: adjustedPoint,
                        fraction: CGFloat(index) / CGFloat(adjustmentMoveCount)
                    ),
                    offset: adjustmentStartOffset + TimeInterval(index) * adjustmentInterval
                )
            )
        }

        guard let record = ShapeFlowTestHelpers.makeGestureRecord(
            named: "Held line adjustment",
            gesture: ShapeFlowTestHelpers.PointerGesture(
                start: start,
                moves: moves,
                liftOffset: adjustmentStartOffset
                    + TimeInterval(adjustmentMoveCount + 1) * adjustmentInterval
            ),
            targetProcessID: ShapeFlowTestHelpers.processID(of: app)
        ) else {
            return XCTFail("XCTest synthesized pointer support is unavailable.")
        }
        XCTAssertTrue(
            ShapeFlowTestHelpers.synthesize(record),
            "failed to synthesize held line adjustment"
        )
    }

    private func interpolate(
        from start: CGPoint,
        to end: CGPoint,
        fraction: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        )
    }
}
