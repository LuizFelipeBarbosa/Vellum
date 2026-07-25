import Darwin
import XCTest

@MainActor
final class ShapeSnapFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHeldPenStrokeSnapsToOneShape() {
        let app = XCUIApplication()
        app.launch()

        openSiteNotes(in: app)
        selectPen(in: app)

        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = shapeCount(of: shapeCountElement)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
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
        XCTAssertEqual(shapeCount(of: shapeCountElement), expectedShapeCount)
    }

    func testHeldLineCanBeAdjustedBeforeLiftAndUndoneOnce() {
        let app = XCUIApplication()
        app.launch()

        openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        clearShapeDrawingArea(in: app, window: window)
        selectPen(in: app)

        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = shapeCount(of: shapeCountElement)

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

        selectBoxTool(in: app)
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
        let vertices = vertices(from: accessibilityValue(of: vertexHandles))
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
        XCTAssertEqual(shapeCount(of: shapeCountElement), shapeCountBefore)
    }

    func testHeldLineSnapsToOneShapeAndUndoesOnce() {
        let app = XCUIApplication()
        app.launch()

        openSiteNotes(in: app)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        clearShapeDrawingArea(in: app, window: window)
        selectPen(in: app)

        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = shapeCount(of: shapeCountElement)

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
        XCTAssertEqual(shapeCount(of: shapeCountElement), expectedShapeCount)

        selectBoxTool(in: app)
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
        let vertices = vertices(from: accessibilityValue(of: vertexHandles))
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
        XCTAssertEqual(shapeCount(of: shapeCountElement), shapeCountBefore)
    }

    private func openSiteNotes(in app: XCUIApplication) {
        let card = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Site notes'")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Site notes card not found")
        card.tap()
    }

    private func selectPen(in app: XCUIApplication) {
        let expandToolbar = app.buttons["Expand toolbar"]
        if expandToolbar.exists {
            expandToolbar.tap()
        }

        let select = app.buttons["Select"]
        let pen = app.buttons["Pen"]
        XCTAssertTrue(select.waitForExistence(timeout: 5), "select tool not found")
        XCTAssertTrue(pen.exists, "pen tool not found")
        select.tap()
        pen.tap()

        let penSelected = expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: pen
        )
        wait(for: [penSelected], timeout: 5)
    }

    private func clearShapeDrawingArea(
        in app: XCUIApplication,
        window: XCUIElement
    ) {
        selectBoxTool(in: app)

        let selectionStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.22, dy: 0.36)
        )
        let selectionEnd = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.74, dy: 0.63)
        )
        selectionStart.press(forDuration: 0.05, thenDragTo: selectionEnd)

        let deleteSelection = app.buttons["Delete selection"]
        if deleteSelection.waitForExistence(timeout: 1) {
            deleteSelection.tap()
        }
    }

    private func selectBoxTool(in app: XCUIApplication) {
        let expandToolbar = app.buttons["Expand toolbar"]
        if expandToolbar.exists {
            expandToolbar.tap()
        }

        let select = app.buttons["Select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5), "select tool not found")
        select.tap()

        let box = app.buttons["Box"]
        XCTAssertTrue(box.waitForExistence(timeout: 5), "boxed selection mode not found")
        box.tap()
    }

    private func shapeCount(of element: XCUIElement) -> Int {
        if let value = element.value as? String, let count = Int(value) {
            return count
        }
        if let value = element.value as? NSNumber {
            return value.intValue
        }
        XCTFail("shape count has unexpected value: \(String(describing: element.value))")
        return -1
    }

    private func accessibilityValue(of element: XCUIElement) -> String {
        guard let value = element.value as? String else {
            XCTFail(
                "shape vertex summary has unexpected value: "
                    + String(describing: element.value)
            )
            return ""
        }
        return value
    }

    private func vertices(from summary: String) -> [CGPoint] {
        summary.split(separator: ";").compactMap { encodedPoint in
            let coordinates = encodedPoint.split(separator: ",")
            guard coordinates.count == 2,
                  let x = Double(coordinates[0]),
                  let y = Double(coordinates[1]) else {
                XCTFail("invalid shape vertex summary: \(summary)")
                return nil
            }
            return CGPoint(x: x, y: y)
        }
    }

    private func performHeldLineAdjustment(
        in app: XCUIApplication,
        from start: CGPoint,
        through dwellPoint: CGPoint,
        to adjustedPoint: CGPoint
    ) {
        guard let messageSendSymbol = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"),
              let pathClass = NSClassFromString("XCPointerEventPath"),
              let recordClass = NSClassFromString("XCSynthesizedEventRecord") else {
            return XCTFail("XCTest synthesized pointer support is unavailable.")
        }

        typealias AllocateMessage = @convention(c) (
            AnyObject,
            Selector
        ) -> Unmanaged<AnyObject>
        typealias PointInitializerMessage = @convention(c) (
            AnyObject,
            Selector,
            CGPoint,
            TimeInterval
        ) -> Unmanaged<AnyObject>
        typealias ObjectInitializerMessage = @convention(c) (
            AnyObject,
            Selector,
            AnyObject
        ) -> Unmanaged<AnyObject>
        typealias DoubleMessage = @convention(c) (
            AnyObject,
            Selector,
            TimeInterval
        ) -> Void
        typealias PointDoubleMessage = @convention(c) (
            AnyObject,
            Selector,
            CGPoint,
            TimeInterval
        ) -> Void
        typealias ObjectMessage = @convention(c) (
            AnyObject,
            Selector,
            AnyObject
        ) -> Void
        typealias IntegerMessage = @convention(c) (
            AnyObject,
            Selector,
            Int64
        ) -> Void
        typealias IntegerReturnMessage = @convention(c) (
            AnyObject,
            Selector
        ) -> Int32
        typealias SynthesizeMessage = @convention(c) (
            AnyObject,
            Selector,
            UnsafeMutablePointer<AnyObject?>?
        ) -> Bool

        let allocate = unsafeBitCast(messageSendSymbol, to: AllocateMessage.self)
        let initializePath = unsafeBitCast(
            messageSendSymbol,
            to: PointInitializerMessage.self
        )
        let initializeRecord = unsafeBitCast(
            messageSendSymbol,
            to: ObjectInitializerMessage.self
        )
        let sendDouble = unsafeBitCast(messageSendSymbol, to: DoubleMessage.self)
        let sendPointDouble = unsafeBitCast(
            messageSendSymbol,
            to: PointDoubleMessage.self
        )
        let sendObject = unsafeBitCast(messageSendSymbol, to: ObjectMessage.self)
        let sendInteger = unsafeBitCast(messageSendSymbol, to: IntegerMessage.self)
        let readInteger = unsafeBitCast(
            messageSendSymbol,
            to: IntegerReturnMessage.self
        )
        let synthesize = unsafeBitCast(messageSendSymbol, to: SynthesizeMessage.self)

        let pathAllocation = allocate(
            pathClass,
            NSSelectorFromString("alloc")
        ).takeRetainedValue()
        let path = initializePath(
            pathAllocation,
            NSSelectorFromString("initForTouchAtPoint:offset:"),
            start,
            0
        ).takeUnretainedValue()
        sendDouble(path, NSSelectorFromString("pressDownAtOffset:"), 0)

        let initialMoveCount = 10
        let initialMoveInterval: TimeInterval = 0.03
        for index in 1...initialMoveCount {
            let fraction = CGFloat(index) / CGFloat(initialMoveCount)
            sendPointDouble(
                path,
                NSSelectorFromString("moveToPoint:atOffset:"),
                interpolate(from: start, to: dwellPoint, fraction: fraction),
                TimeInterval(index) * initialMoveInterval
            )
        }

        // Repeating the exact point prevents XCTest from interpolating movement
        // across what should be the stationary portion of the gesture.
        let holdSampleInterval: TimeInterval = 0.05
        let holdSampleCount = 18
        let holdStartOffset = TimeInterval(initialMoveCount) * initialMoveInterval
        let holdEndOffset =
            holdStartOffset + TimeInterval(holdSampleCount) * holdSampleInterval
        for index in 1...holdSampleCount {
            sendPointDouble(
                path,
                NSSelectorFromString("moveToPoint:atOffset:"),
                dwellPoint,
                holdStartOffset + TimeInterval(index) * holdSampleInterval
            )
        }

        let adjustmentStartOffset = holdEndOffset + holdSampleInterval
        let adjustmentMoveCount = 8
        for index in 1...adjustmentMoveCount {
            let fraction = CGFloat(index) / CGFloat(adjustmentMoveCount)
            sendPointDouble(
                path,
                NSSelectorFromString("moveToPoint:atOffset:"),
                interpolate(
                    from: dwellPoint,
                    to: adjustedPoint,
                    fraction: fraction
                ),
                adjustmentStartOffset + TimeInterval(index) * 0.04
            )
        }
        sendDouble(
            path,
            NSSelectorFromString("liftUpAtOffset:"),
            adjustmentStartOffset + TimeInterval(adjustmentMoveCount + 1) * 0.04
        )

        let recordAllocation = allocate(
            recordClass,
            NSSelectorFromString("alloc")
        ).takeRetainedValue()
        let record = initializeRecord(
            recordAllocation,
            NSSelectorFromString("initWithName:"),
            "Held line adjustment" as NSString
        ).takeUnretainedValue()
        sendInteger(
            record,
            NSSelectorFromString("setTargetProcessID:"),
            Int64(readInteger(app, NSSelectorFromString("processID")))
        )
        sendObject(
            record,
            NSSelectorFromString("addPointerEventPath:"),
            path
        )

        var synthesisError: AnyObject?
        let succeeded = synthesize(
            record,
            NSSelectorFromString("synthesizeWithError:"),
            &synthesisError
        )
        XCTAssertTrue(
            succeeded,
            "failed to synthesize held line adjustment: "
                + String(describing: synthesisError)
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
