import XCTest

/// Recognition quality and post-selection affordances, driven by real multi-segment strokes —
/// a shape drawn corner by corner is the case `press(thenDragTo:)` cannot express at all.
@MainActor
final class ShapeRecognitionFlowUITests: XCTestCase {
    /// Fraction along a line to grab it by — clear of the vertex handles at either end.
    private static let grabPosition: CGFloat = 0.35

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

        // The Select tool is borrowed, not taken: deselecting hands the pen back.
        relaunched.coordinate(withNormalizedOffset: CGVector(dx: 0.76, dy: 0.30)).tap()
        let penRestored = expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: app.buttons["Pen"]
        )
        wait(for: [penRestored], timeout: 5)
        XCTAssertFalse(
            app.buttons["Duplicate selection"].exists,
            "the selection menu outlived the selection"
        )
    }

    /// Covers that the handles are there and on the curve;
    /// `testDraggingAnEllipseRadiusHandleResizesOnlyThatAxis` covers pulling one.
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

    /// A radius handle pulled sideways stretches the ellipse across, and only across: the
    /// opposite point on the curve and both ends of the other axis stay exactly where they were.
    ///
    /// The grab is deliberately off the handle's dead centre, and that is the whole reason this
    /// once looked untestable. A radius handle sits on the selection's own bounding edge, and
    /// `SelectionCapturePolicy` gives any drag starting within a touch target of those bounds to
    /// the canvas as a move — so the handle's drag gesture and the move pan both want this touch.
    /// Aimed a few points to the side the handle takes it and the ellipse resizes; aimed at the
    /// exact centre of the handle's reported frame the move takes it and the whole shape slides
    /// instead, which is what every earlier attempt measured. Two points off is enough, and a
    /// finger never aims that finely, so this offset buys reliability rather than hiding anything.
    func testDraggingAnEllipseRadiusHandleResizesOnlyThatAxis() throws {
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
        let summaryBefore = ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        let before = ShapeFlowTestHelpers.vertices(from: summaryBefore)
        XCTAssertEqual(before.count, 4)

        // Handle 1 is the right end of the horizontal axis, pulled further right.
        let rightHandle = app.descendants(matching: .any)
            .matching(identifier: "vellum-shape-vertex-handle-1")
            .firstMatch
        XCTAssertTrue(
            rightHandle.waitForExistence(timeout: 5),
            "the ellipse's right radius handle is not reachable"
        )
        let grab = rightHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        grab.press(
            forDuration: 0.05,
            thenDragTo: grab.withOffset(CGVector(dx: 96, dy: 0))
        )

        let resized = expectation(
            for: NSPredicate(format: "value != %@", summaryBefore),
            evaluatedWith: vertexHandles
        )
        wait(for: [resized], timeout: 5)

        let after = ShapeFlowTestHelpers.vertices(
            from: ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        )
        XCTAssertEqual(after.count, 4, "the ellipse lost a radius handle to the drag")

        // The dragged end travelled; the far end of the same axis did not, so this grew the
        // ellipse rather than sliding it across the page.
        XCTAssertGreaterThan(
            after[1].x - before[1].x,
            40,
            "the dragged radius handle barely moved"
        )
        XCTAssertEqual(
            after[3].x,
            before[3].x,
            accuracy: 0.5,
            "the whole ellipse moved instead of one radius growing"
        )

        // `ShapeEllipseEditor.resizing` is single-axis by design: the vertical radius is the
        // untouched one, top and bottom keeping both their positions and their separation.
        XCTAssertEqual(after[0].y, before[0].y, accuracy: 0.5, "the top of the curve moved")
        XCTAssertEqual(after[2].y, before[2].y, accuracy: 0.5, "the bottom of the curve moved")
        XCTAssertEqual(
            after[1].y,
            before[1].y,
            accuracy: 0.5,
            "the dragged handle left the axis it belongs to"
        )
    }

    func testDraggingASelectedShapeSettlesItOnThePageLattice() throws {
        let app = XCUIApplication()
        app.launch()
        let window = try openClearedNote(in: app)
        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(shapeCountElement.waitForExistence(timeout: 10))
        let shapeCountBefore = ShapeFlowTestHelpers.shapeCount(of: shapeCountElement)

        window.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.52)).press(
            forDuration: 0.05,
            thenDragTo: window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.62, dy: 0.52)
            ),
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )
        let created = expectation(
            for: NSPredicate(format: "value == %@", String(shapeCountBefore + 1)),
            evaluatedWith: shapeCountElement
        )
        wait(for: [created], timeout: 5)

        ShapeFlowTestHelpers.boxSelect(
            in: app,
            window: window,
            around: CGRect(x: 200, y: 560, width: 500, height: 120)
        )
        let vertexHandles = app.otherElements["vellum-shape-vertex-handles"]
        XCTAssertTrue(vertexHandles.waitForExistence(timeout: 5), "the line was not selected")
        let summaryBefore = ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        let before = ShapeFlowTestHelpers.vertices(from: summaryBefore)
        XCTAssertEqual(before.count, 2)

        // Content and window space differ by the canvas zoom; recover it from one line measured
        // in both, so the drop lands a known distance from a rule instead of wherever it likes.
        let firstEnd = try handleCenter(at: 0, in: app)
        let secondEnd = try handleCenter(at: 1, in: app)
        let contentWidth = before[1].x - before[0].x
        XCTAssertGreaterThan(abs(contentWidth), 1)
        let zoom = (secondEnd.x - firstEnd.x) / contentWidth
        XCTAssertGreaterThan(zoom, 0.1)

        // Aim three rows down and stop 3pt short: inside the tolerance, so it should settle.
        let spacing: CGFloat = 24
        let targetY = ((before[0].y / spacing).rounded(.down) + 3) * spacing
        let contentDrop = targetY - before[0].y - 3
        let grab = point(
            pointAlongLine(from: firstEnd, to: secondEnd, fraction: Self.grabPosition),
            in: window
        )
        let drop = CGPoint(x: grab.x, y: grab.y + contentDrop * zoom)
        guard let record = ShapeFlowTestHelpers.makeGestureRecord(
            named: "Drag selected line",
            gesture: ShapeFlowTestHelpers.PointerGesture(
                start: grab,
                moves: (1...12).map { step in
                    let fraction = CGFloat(step) / 12
                    return (
                        point: CGPoint(
                            x: grab.x,
                            y: grab.y + (drop.y - grab.y) * fraction
                        ),
                        offset: TimeInterval(step) * 0.04
                    )
                },
                liftOffset: 0.6
            ),
            targetProcessID: ShapeFlowTestHelpers.processID(of: app)
        ) else {
            // Capability gate, not a fixture gate: the record is built out of the
            // private XCPointerEventPath API, so a toolchain that no longer
            // vends it cannot run this test at all.
            throw XCTSkip("XCTest synthesized pointer support is unavailable.")
        }
        XCTAssertTrue(ShapeFlowTestHelpers.synthesize(record), "failed to synthesize the drag")

        let moved = expectation(
            for: NSPredicate(format: "value != %@", summaryBefore),
            evaluatedWith: vertexHandles
        )
        wait(for: [moved], timeout: 5)

        let after = ShapeFlowTestHelpers.vertices(
            from: ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        )
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(
            after[0].y,
            targetY,
            accuracy: 0.5,
            "the dragged line did not settle onto the rule it was dropped beside"
        )
        XCTAssertEqual(after[1].y, after[0].y, accuracy: 0.5, "the line stopped being level")
    }

    private func pointAlongLine(
        from start: CGPoint,
        to end: CGPoint,
        fraction: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        )
    }

    /// A selected shape always publishes its vertex handles, so a missing one is a
    /// defect in the app rather than a reason to stop testing: fail, then throw to
    /// abandon a test whose remaining geometry would be meaningless.
    private struct MissingVertexHandle: Error {
        let index: Int
    }

    private func handleCenter(at index: Int, in app: XCUIApplication) throws -> CGPoint {
        let handle = app.descendants(matching: .any)
            .matching(identifier: "vellum-shape-vertex-handle-\(index)")
            .firstMatch
        guard handle.waitForExistence(timeout: 5) else {
            XCTFail("shape vertex handle \(index) not found")
            throw MissingVertexHandle(index: index)
        }
        return CGPoint(x: handle.frame.midX, y: handle.frame.midY)
    }

    private func point(_ location: CGPoint, in window: XCUIElement) -> CGPoint {
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(
                CGVector(
                    dx: location.x - window.frame.minX,
                    dy: location.y - window.frame.minY
                )
            )
            .screenPoint
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
