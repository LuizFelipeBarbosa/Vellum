import XCTest

@MainActor
final class SelectionMoveFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A small shape has almost no room to grab inside its own bounds, so a drag starting
    /// well outside the selection must still translate it instead of starting a new capture.
    func testDraggingOutsideSelectionMovesIt() {
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
            thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.58)),
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )
        let snapped = expectation(
            for: NSPredicate(format: "value == %@", String(shapeCountBefore + 1)),
            evaluatedWith: shapeCountElement
        )
        wait(for: [snapped], timeout: 5)

        ShapeFlowTestHelpers.selectTool("Select", in: app)
        ShapeFlowTestHelpers.selectTool("Box", in: app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.26, dy: 0.54)).press(
            forDuration: 0.05,
            thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.62))
        )

        let vertexHandles = app.otherElements["vellum-shape-vertex-handles"]
        XCTAssertTrue(
            vertexHandles.waitForExistence(timeout: 5),
            "shape vertex handles did not appear after boxed selection"
        )
        let summaryBefore = ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        let pointsBefore = ShapeFlowTestHelpers.vertices(from: summaryBefore)
        guard pointsBefore.count >= 2 else {
            XCTFail("selected shape exposes fewer than two vertices")
            return
        }

        // Far below and to the right of both the selection and its action strip.
        let outsideStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.68, dy: 0.70)
        )
        outsideStart.press(
            forDuration: 0.05,
            thenDragTo: outsideStart.withOffset(CGVector(dx: -70, dy: -60))
        )

        let moved = expectation(
            for: NSPredicate(format: "value != %@", summaryBefore),
            evaluatedWith: vertexHandles
        )
        wait(for: [moved], timeout: 5)

        let pointsAfter = ShapeFlowTestHelpers.vertices(
            from: ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        )
        guard pointsAfter.count == pointsBefore.count else {
            XCTFail("a drag outside the selection replaced it instead of moving it")
            return
        }

        let shift = CGVector(
            dx: pointsAfter[0].x - pointsBefore[0].x,
            dy: pointsAfter[0].y - pointsBefore[0].y
        )
        XCTAssertLessThan(shift.dx, -10, "the selection did not follow the drag leftward")
        XCTAssertLessThan(shift.dy, -10, "the selection did not follow the drag upward")

        // Every vertex shifts alike: a translation, not a reshape or a fresh selection.
        for (before, after) in zip(pointsBefore, pointsAfter) {
            XCTAssertEqual(after.x - before.x, shift.dx, accuracy: 1)
            XCTAssertEqual(after.y - before.y, shift.dy, accuracy: 1)
        }
    }
}
