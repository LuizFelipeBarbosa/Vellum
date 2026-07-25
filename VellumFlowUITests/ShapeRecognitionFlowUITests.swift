import XCTest

/// Recognition quality and post-selection affordances, driven by real multi-segment strokes —
/// a shape drawn corner by corner is the case `press(thenDragTo:)` cannot express at all.
@MainActor
final class ShapeRecognitionFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testASquareDrawnWithAGapSnapsToFourCorners() throws {
        let app = XCUIApplication()
        app.launch()
        let window = try openClearedNote(in: app)
        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = ShapeFlowTestHelpers.shapeCount(of: shapeCountElement)

        // Four corners, coming back around to 20pt short of the start — the way a hand closes a
        // square. Before the closure fix this produced a five-cornered polygon.
        let square = CGRect(x: 240, y: 480, width: 200, height: 200)
        ShapeFlowTestHelpers.drawStroke(
            in: app,
            window: window,
            through: [
                CGPoint(x: square.minX, y: square.minY),
                CGPoint(x: square.maxX, y: square.minY),
                CGPoint(x: square.maxX, y: square.maxY),
                CGPoint(x: square.minX, y: square.maxY),
                CGPoint(x: square.minX, y: square.minY + 20),
            ]
        )

        let snapped = expectation(
            for: NSPredicate(format: "value == %@", String(shapeCountBefore + 1)),
            evaluatedWith: shapeCountElement
        )
        wait(for: [snapped], timeout: 5)

        ShapeFlowTestHelpers.boxSelect(
            in: app,
            window: window,
            around: square.insetBy(dx: -40, dy: -40)
        )
        let vertexHandles = app.otherElements["vellum-shape-vertex-handles"]
        XCTAssertTrue(
            vertexHandles.waitForExistence(timeout: 5),
            "the snapped square exposed no vertex handles"
        )

        let vertices = ShapeFlowTestHelpers.vertices(
            from: ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        )
        XCTAssertEqual(vertices.count, 4, "a gapped square did not close into four corners")

        let sides = vertices.indices.map { index -> CGFloat in
            let next = vertices[(index + 1) % vertices.count]
            return hypot(next.x - vertices[index].x, next.y - vertices[index].y)
        }
        for side in sides {
            XCTAssertEqual(side, sides[0], accuracy: 1, "the square's sides are uneven")
        }
    }

    func testTappingAShapeOpensTheSelectionMenu() throws {
        let app = XCUIApplication()
        app.launch()
        let window = try openClearedNote(in: app)
        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(shapeCountElement.waitForExistence(timeout: 10))
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

        // Relaunch pencil-only so a finger tap selects instead of drawing.
        app.terminate()
        app.launchArguments = ["-vellum-force-pencil-only"]
        app.launch()
        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let relaunched = app.windows.firstMatch
        XCTAssertTrue(relaunched.waitForExistence(timeout: 5))

        XCTAssertFalse(
            app.buttons["Duplicate selection"].exists,
            "the selection menu was showing before anything was selected"
        )
        relaunched.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.58)).tap()

        XCTAssertTrue(
            app.buttons["Duplicate selection"].waitForExistence(timeout: 5),
            "tapping a shape did not open the selection menu"
        )
        XCTAssertTrue(app.buttons["Delete selection"].exists)
        XCTAssertTrue(app.buttons["Style selection"].exists)

        // The tap puts the canvas in the same state the Select tool would: one way to edit a
        // shape, not a tap-only variant with its own rules.
        XCTAssertTrue(
            app.buttons["Select"].isSelected,
            "tapping a shape did not switch to the Select tool"
        )
        XCTAssertTrue(
            app.otherElements["vellum-shape-vertex-handles"].waitForExistence(timeout: 5),
            "the tapped shape exposed no edit handles"
        )
    }

    /// Covers that the handles are there and on the curve. Dragging one is covered by
    /// `ElementUndoTransactionTests`, not here: a synthesized drag on these handles does not
    /// resize the ellipse even though the identical gesture works on polyline vertex handles,
    /// which is unexplained and needs a pass on a real device before it can be called working.
    func testAnEllipseExposesFourRadiusHandlesOnItsCurve() throws {
        let app = XCUIApplication()
        app.launch()
        let window = try openClearedNote(in: app)
        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(shapeCountElement.waitForExistence(timeout: 10))
        let shapeCountBefore = ShapeFlowTestHelpers.shapeCount(of: shapeCountElement)

        let box = CGRect(x: 240, y: 470, width: 220, height: 160)
        ShapeFlowTestHelpers.drawStroke(
            in: app,
            window: window,
            through: ellipsePath(in: box)
        )
        let snapped = expectation(
            for: NSPredicate(format: "value == %@", String(shapeCountBefore + 1)),
            evaluatedWith: shapeCountElement
        )
        wait(for: [snapped], timeout: 5)

        ShapeFlowTestHelpers.boxSelect(
            in: app,
            window: window,
            around: box.insetBy(dx: -40, dy: -40)
        )
        let vertexHandles = app.otherElements["vellum-shape-vertex-handles"]
        XCTAssertTrue(
            vertexHandles.waitForExistence(timeout: 5),
            "the ellipse exposed no radius handles"
        )
        let handles = ShapeFlowTestHelpers.vertices(
            from: ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        )
        XCTAssertEqual(handles.count, 4, "an ellipse should offer one handle per axis end")

        // Each handle sits on the curve — top and bottom share the center's x, left and right
        // share its y — rather than on the corners of a box around it.
        XCTAssertEqual(handles[0].x, handles[2].x, accuracy: 0.5)
        XCTAssertEqual(handles[1].y, handles[3].y, accuracy: 0.5)
        XCTAssertLessThan(handles[0].y, handles[2].y)
        XCTAssertLessThan(handles[3].x, handles[1].x)

        // Every handle is individually addressable, which is what makes them grabbable.
        for index in 0..<4 {
            let handle = app.descendants(matching: .any)
                .matching(identifier: "vellum-shape-vertex-handle-\(index)")
                .firstMatch
            XCTAssertTrue(
                handle.waitForExistence(timeout: 5),
                "radius handle \(index) is not reachable"
            )
        }
    }

    private func openClearedNote(in app: XCUIApplication) throws -> XCUIElement {
        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        ShapeFlowTestHelpers.clearShapeDrawingArea(
            in: app,
            window: window,
            selectionStart: CGVector(dx: 0.18, dy: 0.30),
            selectionEnd: CGVector(dx: 0.84, dy: 0.80)
        )
        ShapeFlowTestHelpers.selectTool("Pen", in: app)
        return window
    }

    /// A closed ellipse traced in 24 steps, ending back where it started.
    private func ellipsePath(in box: CGRect) -> [CGPoint] {
        let steps = 24
        return (0...steps).map { step in
            let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
            return CGPoint(
                x: box.midX + box.width / 2 * cos(angle),
                y: box.midY + box.height / 2 * sin(angle)
            )
        }
    }
}
