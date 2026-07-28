import XCTest

@MainActor
final class SelectionMoveFlowUITests: XCTestCase {
    /// Mirrors `SelectionCapturePolicy.grabPadding` — this target does not link VellumCore, so
    /// the number is repeated here. It is a screen measurement, which is also what a synthesized
    /// gesture speaks, so every offset below is in screen points.
    private let grabPadding: CGFloat = 22

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A snapped line is eight content points tall: there is no interior to aim at, and a drag
    /// that had to begin inside the selection bounds could not move it at all. The grab area is
    /// those bounds padded to a comfortable touch target, and this drives both of its edges —
    /// a drag starting beside the line moves it, one starting well past the padding does not.
    ///
    /// What the far drag does instead is this run's answer, not hardware's: fingers may capture
    /// in the simulator, so it starts a fresh capture. On a device — or under
    /// `-vellum-force-pencil-only`, which this test deliberately does not pass — the same drag
    /// falls through to the canvas and scrolls it. Both rest on the one claim asserted here:
    /// a drag beginning outside the grab area does not belong to the selection.
    func testDraggingBesideSmallSelectionMovesItButDraggingFarFromItDoesNot() {
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

        let vertexHandles = app.otherElements["vellum-shape-vertex-handles"]
        selectDrawnLine(in: app, window: window)
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

        // The two vertex handles sit on the line's endpoints, so their spread on screen against
        // the same two vertices in content space is whatever zoom the canvas is at. Offsetting
        // from a handle's own center keeps the arithmetic in screen points throughout.
        let firstHandle = vertexHandle(0, in: app)
        let firstCenter = center(of: firstHandle)
        let secondCenter = center(of: vertexHandle(1, in: app))
        let screenSpan = hypot(secondCenter.x - firstCenter.x, secondCenter.y - firstCenter.y)
        let contentSpan = hypot(
            pointsBefore[1].x - pointsBefore[0].x,
            pointsBefore[1].y - pointsBefore[0].y
        )
        guard screenSpan > 0, contentSpan > 0 else {
            XCTFail("the selected line has no length to measure the canvas zoom with")
            return
        }
        let zoomScale = screenSpan / contentSpan

        // A shape's frame is inflated to at least eight content points, so the selection bounds
        // reach only this far below the line — a handful of screen points, which is the whole
        // reason the padding exists.
        let boundsEdge = max(abs(pointsBefore[1].y - pointsBefore[0].y), 8) / 2 * zoomScale
        let midpoint = CGPoint(
            x: (firstCenter.x + secondCenter.x) / 2,
            y: (firstCenter.y + secondCenter.y) / 2
        )
        let anchor = firstHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        func startBelowLine(by distance: CGFloat) -> XCUICoordinate {
            anchor.withOffset(
                CGVector(
                    dx: midpoint.x - firstCenter.x,
                    dy: midpoint.y - firstCenter.y + distance
                )
            )
        }

        // Three targets below the line: past any padding, and far enough that the capture this
        // starts cannot reach back over the shape.
        let farStart = startBelowLine(by: boundsEdge + grabPadding * 3)
        farStart.press(
            forDuration: 0.05,
            thenDragTo: farStart.withOffset(CGVector(dx: 60, dy: 40))
        )
        XCTAssertTrue(
            vertexHandles.waitForNonExistence(timeout: 5),
            "a drag well outside the grab area still belonged to the selection"
        )

        selectDrawnLine(in: app, window: window)
        XCTAssertTrue(
            vertexHandles.waitForExistence(timeout: 5),
            "the line could not be selected again after the capture"
        )
        XCTAssertEqual(
            ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles),
            summaryBefore,
            "a drag well outside the grab area moved the selection"
        )

        // Halfway through the padding: outside the line's own bounds, where the drag used to
        // start a capture over the selection it was reaching for, and inside the grab area.
        let besideStart = startBelowLine(by: boundsEdge + grabPadding / 2)
        besideStart.press(
            forDuration: 0.05,
            thenDragTo: besideStart.withOffset(CGVector(dx: -70, dy: -60))
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
            XCTFail("a drag beside the selection replaced it instead of moving it")
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

    /// Physical devices leave a finger drag outside the selection's grab area to the canvas,
    /// keeping one-finger scrolling reachable while something is selected. The simulator's
    /// default finger-capture path cannot express that contract, so the pencil-only launch
    /// override pins both halves of it: the document stays unchanged and the canvas scrolls.
    func testFingerDragOutsideSelectionGrabAreaScrollsCanvasWithoutMovingSelection() {
        let context = ShapeFlowTestHelpers
            .preparePersistedLineShapeForPencilOnlyRelaunch(using: self)

        context.shapeMiddle.tap()

        let vertexHandles = context.app.otherElements["vellum-shape-vertex-handles"]
        XCTAssertTrue(
            vertexHandles.waitForExistence(timeout: 5),
            "shape vertex handles did not appear after a pencil-only finger tap"
        )
        let summaryBefore = ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        guard !summaryBefore.isEmpty else {
            XCTFail("selected shape exposed an empty vertex summary before scrolling")
            return
        }
        let pointsBefore = ShapeFlowTestHelpers.vertices(from: summaryBefore)
        guard pointsBefore.count >= 2 else {
            XCTFail("selected shape exposes fewer than two vertices")
            return
        }

        let firstHandle = vertexHandle(0, in: context.app)
        let firstCenterBefore = center(of: firstHandle)
        let secondCenterBefore = center(of: vertexHandle(1, in: context.app))
        let screenSpan = hypot(
            secondCenterBefore.x - firstCenterBefore.x,
            secondCenterBefore.y - firstCenterBefore.y
        )
        let contentSpan = hypot(
            pointsBefore[1].x - pointsBefore[0].x,
            pointsBefore[1].y - pointsBefore[0].y
        )
        guard screenSpan > 0, contentSpan > 0 else {
            XCTFail("the selected line has no length to measure the canvas zoom with")
            return
        }
        let zoomScale = screenSpan / contentSpan

        let boundsEdge = max(abs(pointsBefore[1].y - pointsBefore[0].y), 8)
            / 2 * zoomScale
        let midpoint = CGPoint(
            x: (firstCenterBefore.x + secondCenterBefore.x) / 2,
            y: (firstCenterBefore.y + secondCenterBefore.y) / 2
        )
        let anchor = firstHandle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        let dragStart = anchor.withOffset(
            CGVector(
                dx: midpoint.x - firstCenterBefore.x,
                dy: midpoint.y - firstCenterBefore.y + boundsEdge + grabPadding * 3
            )
        )
        let dragDistance: CGFloat = 180
        let dragEnd = dragStart.withOffset(CGVector(dx: 0, dy: -dragDistance))
        guard context.window.frame.contains(dragStart.screenPoint),
              context.window.frame.contains(dragEnd.screenPoint) else {
            XCTFail("the measured scroll drag path left the canvas window")
            return
        }

        // This central strip is clear of the docked toolbar. Holding a slow drag still before
        // lifting removes momentum, so the line's predicted resting point follows the applied
        // finger delta closely enough to re-select it if scrolling happens to clear the handles.
        dragStart.press(
            forDuration: 0.05,
            thenDragTo: dragEnd,
            withVelocity: .slow,
            thenHoldForDuration: 1.0
        )

        let selectionBranch: String
        if vertexHandles.waitForNonExistence(timeout: 1) {
            selectionBranch = "selection cleared during scroll"
            let predictedMiddle = CGPoint(
                x: midpoint.x,
                y: midpoint.y - dragDistance
            )
            let windowOrigin = context.window.coordinate(withNormalizedOffset: .zero)
            windowOrigin.withOffset(
                CGVector(
                    dx: predictedMiddle.x - windowOrigin.screenPoint.x,
                    dy: predictedMiddle.y - windowOrigin.screenPoint.y
                )
            ).tap()
            guard vertexHandles.waitForExistence(timeout: 5) else {
                XCTFail(
                    "could not re-select the scrolled shape at its predicted position "
                        + "(\(selectionBranch))"
                )
                return
            }
        } else {
            selectionBranch = "selection survived scroll"
            guard vertexHandles.waitForExistence(timeout: 1) else {
                XCTFail("shape handles did not settle after the drag (\(selectionBranch))")
                return
            }
        }

        let summaryAfter = ShapeFlowTestHelpers.accessibilityValue(of: vertexHandles)
        guard !summaryAfter.isEmpty else {
            XCTFail("selected shape exposed an empty post-scroll summary (\(selectionBranch))")
            return
        }
        XCTAssertEqual(
            summaryAfter,
            summaryBefore,
            "the outside finger drag mutated the selected shape (\(selectionBranch))"
        )

        let firstCenterAfter = center(of: vertexHandle(0, in: context.app))
        let secondCenterAfter = center(of: vertexHandle(1, in: context.app))
        let firstVerticalShift = firstCenterAfter.y - firstCenterBefore.y
        let secondVerticalShift = secondCenterAfter.y - secondCenterBefore.y
        let minimumScrollShift = dragDistance / 4
        XCTAssertLessThan(
            firstVerticalShift,
            -minimumScrollShift,
            "the first handle did not move upward with the scrolled canvas "
                + "(\(selectionBranch))"
        )
        XCTAssertLessThan(
            secondVerticalShift,
            -minimumScrollShift,
            "the second handle did not move upward with the scrolled canvas "
                + "(\(selectionBranch))"
        )
    }

    /// Boxes the drawn line with a rectangle that clears it on every side, so the selection this
    /// makes is the same one however often it is remade.
    private func selectDrawnLine(in app: XCUIApplication, window: XCUIElement) {
        ShapeFlowTestHelpers.selectTool("Select", in: app)
        ShapeFlowTestHelpers.selectTool("Box", in: app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.26, dy: 0.54)).press(
            forDuration: 0.05,
            thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.62))
        )
    }

    private func vertexHandle(
        _ index: Int,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let handle = app.descendants(matching: .any)
            .matching(identifier: "vellum-shape-vertex-handle-\(index)")
            .firstMatch
        XCTAssertTrue(
            handle.waitForExistence(timeout: 5),
            "shape vertex handle \(index) not found",
            file: file,
            line: line
        )
        return handle
    }

    private func center(of element: XCUIElement) -> CGPoint {
        let frame = element.frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}
