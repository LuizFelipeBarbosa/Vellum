import XCTest

@MainActor
final class ShapeInteractionFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEraserDragRemovesShape() {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        ShapeFlowTestHelpers.clearShapeDrawingArea(
            in: app,
            window: window,
            selectionStart: CGVector(dx: 0.22, dy: 0.38),
            selectionEnd: CGVector(dx: 0.80, dy: 0.76)
        )
        ShapeFlowTestHelpers.selectTool("Pen", in: app)

        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = ShapeFlowTestHelpers.shapeCount(of: shapeCountElement)

        let shapeStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.30, dy: 0.58)
        )
        let shapeEnd = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.58, dy: 0.58)
        )
        shapeStart.press(
            forDuration: 0.05,
            thenDragTo: shapeEnd,
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )

        let countAfterCreation = shapeCountBefore + 1
        let created = expectation(
            for: NSPredicate(format: "value == %@", String(countAfterCreation)),
            evaluatedWith: shapeCountElement
        )
        wait(for: [created], timeout: 5)

        ShapeFlowTestHelpers.selectTool("Eraser", in: app)
        let eraserStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.44, dy: 0.54)
        )
        let eraserEnd = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.44, dy: 0.62)
        )
        eraserStart.press(forDuration: 0.05, thenDragTo: eraserEnd)

        let erased = expectation(
            for: NSPredicate(format: "value == %@", String(shapeCountBefore)),
            evaluatedWith: shapeCountElement
        )
        wait(for: [erased], timeout: 5)
        XCTAssertEqual(
            ShapeFlowTestHelpers.shapeCount(of: shapeCountElement),
            shapeCountBefore
        )
    }

    /// The shape must vanish under the eraser on contact — not when the pencil lifts.
    /// Proven by running a deliberately long erase gesture on a background queue and
    /// watching the shape count drop while the touch is still down.
    func testEraserRemovesShapeWhileThePencilIsStillDown() {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        ShapeFlowTestHelpers.clearShapeDrawingArea(
            in: app,
            window: window,
            selectionStart: CGVector(dx: 0.22, dy: 0.38),
            selectionEnd: CGVector(dx: 0.80, dy: 0.76)
        )
        ShapeFlowTestHelpers.selectTool("Pen", in: app)

        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = ShapeFlowTestHelpers.shapeCount(of: shapeCountElement)

        window.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.58)).press(
            forDuration: 0.05,
            thenDragTo: window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.58, dy: 0.58)
            ),
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )
        let created = expectation(
            for: NSPredicate(format: "value == %@", String(shapeCountBefore + 1)),
            evaluatedWith: shapeCountElement
        )
        wait(for: [created], timeout: 5)

        ShapeFlowTestHelpers.selectTool("Eraser", in: app)

        guard let record = makeSlowEraseGestureRecord(in: app, window: window) else {
            return XCTFail("XCTest synthesized pointer support is unavailable.")
        }
        let gestureFinished = XCTestExpectation(description: "erase gesture finished")
        let startedAt = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertTrue(
                ShapeFlowTestHelpers.synthesize(record),
                "failed to synthesize the erase gesture"
            )
            gestureFinished.fulfill()
        }

        // The gesture crosses the shape ~0.3s in and does not lift until ~3.4s, so a
        // count drop inside this window can only have happened with the touch still down.
        let stillDownDeadline: TimeInterval = 2
        var erasedAfter: TimeInterval?
        while Date().timeIntervalSince(startedAt) < stillDownDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if (shapeCountElement.value as? String).flatMap(Int.init) == shapeCountBefore {
                erasedAfter = Date().timeIntervalSince(startedAt)
                break
            }
        }

        wait(for: [gestureFinished], timeout: 15)
        guard let erasedAfter else {
            return XCTFail("the shape was not erased until the pencil lifted")
        }
        XCTAssertLessThan(erasedAfter, stillDownDeadline)
        XCTAssertEqual(
            ShapeFlowTestHelpers.shapeCount(of: shapeCountElement),
            shapeCountBefore
        )
    }

    /// Presses above the shape, crosses it over ~0.3s, then holds still for 3s before lifting.
    private func makeSlowEraseGestureRecord(
        in app: XCUIApplication,
        window: XCUIElement
    ) -> ShapeFlowTestHelpers.GestureRecord? {
        let start = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.44, dy: 0.52)
        ).screenPoint
        let end = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.44, dy: 0.64)
        ).screenPoint

        var moves: [(point: CGPoint, offset: TimeInterval)] = []
        let crossingSteps = 6
        let crossingInterval: TimeInterval = 0.05
        for index in 1...crossingSteps {
            let fraction = CGFloat(index) / CGFloat(crossingSteps)
            moves.append(
                (
                    point: CGPoint(
                        x: start.x + (end.x - start.x) * fraction,
                        y: start.y + (end.y - start.y) * fraction
                    ),
                    offset: TimeInterval(index) * crossingInterval
                )
            )
        }

        // Repeating the exact point keeps XCTest from interpolating motion across the hold.
        let holdStart = TimeInterval(crossingSteps) * crossingInterval
        let holdInterval: TimeInterval = 0.1
        let holdSamples = 30
        for index in 1...holdSamples {
            moves.append(
                (point: end, offset: holdStart + TimeInterval(index) * holdInterval)
            )
        }

        return ShapeFlowTestHelpers.makeGestureRecord(
            named: "Slow eraser drag",
            gesture: ShapeFlowTestHelpers.PointerGesture(
                start: start,
                moves: moves,
                liftOffset: holdStart + TimeInterval(holdSamples + 1) * holdInterval
            ),
            targetProcessID: ShapeFlowTestHelpers.processID(of: app)
        )
    }

    func testFingerTapOnShapeShowsVertexHandles() {
        let context = preparePersistedLineShapeForPencilOnlyRelaunch()

        context.shapeMiddle.tap()

        let vertexHandles = context.app.otherElements["vellum-shape-vertex-handles"]
        XCTAssertTrue(
            vertexHandles.waitForExistence(timeout: 5),
            "shape vertex handles did not appear after a finger tap"
        )
        let vertices = ShapeFlowTestHelpers.vertices(
            from: ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        )
        XCTAssertEqual(vertices.count, 2)
    }

    func testFingerTapOnEmptyCanvasClearsHandles() {
        let context = preparePersistedLineShapeForPencilOnlyRelaunch()

        context.shapeMiddle.tap()

        let vertexHandles = context.app.otherElements["vellum-shape-vertex-handles"]
        XCTAssertTrue(
            vertexHandles.waitForExistence(timeout: 5),
            "shape vertex handles did not appear after a finger tap"
        )

        context.window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.76, dy: 0.72)
        ).tap()

        XCTAssertTrue(
            vertexHandles.waitForNonExistence(timeout: 5),
            "shape vertex handles remained after tapping empty canvas"
        )
    }

    private func preparePersistedLineShapeForPencilOnlyRelaunch() -> (
        app: XCUIApplication,
        window: XCUIElement,
        shapeMiddle: XCUICoordinate
    ) {
        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        ShapeFlowTestHelpers.clearShapeDrawingArea(
            in: app,
            window: window,
            selectionStart: CGVector(dx: 0.22, dy: 0.38),
            selectionEnd: CGVector(dx: 0.80, dy: 0.76)
        )
        ShapeFlowTestHelpers.selectTool("Pen", in: app)

        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = ShapeFlowTestHelpers.shapeCount(of: shapeCountElement)

        let shapeStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.30, dy: 0.58)
        )
        let shapeEnd = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.58, dy: 0.58)
        )
        shapeStart.press(
            forDuration: 0.05,
            thenDragTo: shapeEnd,
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )

        let created = expectation(
            for: NSPredicate(format: "value == %@", String(shapeCountBefore + 1)),
            evaluatedWith: shapeCountElement
        )
        wait(for: [created], timeout: 5)

        app.terminate()
        app.launchArguments = ["-vellum-force-pencil-only"]
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)

        let relaunchedWindow = app.windows.firstMatch
        XCTAssertTrue(
            relaunchedWindow.waitForExistence(timeout: 5),
            "app window not found after pencil-only relaunch"
        )
        let shapeMiddle = relaunchedWindow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.44, dy: 0.58)
        )
        return (app, relaunchedWindow, shapeMiddle)
    }
}
