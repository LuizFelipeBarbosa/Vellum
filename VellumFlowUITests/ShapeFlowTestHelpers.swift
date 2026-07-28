import Darwin
import XCTest

@MainActor
enum ShapeFlowTestHelpers {
    /// A synthesized single-touch gesture: press at `start`, visit each move in order,
    /// then lift. Offsets are seconds from the press. Repeat a point to hold still —
    /// XCTest interpolates motion between distinct points.
    struct PointerGesture {
        var start: CGPoint
        var moves: [(point: CGPoint, offset: TimeInterval)]
        var liftOffset: TimeInterval
    }

    /// A built-but-not-yet-synthesized event record. The wrapped ObjC object is only ever
    /// handed to `synthesize`, so crossing a queue boundary with it is safe.
    struct GestureRecord: @unchecked Sendable {
        fileprivate let record: AnyObject
        /// The record does not keep the pointer path alive on its own.
        fileprivate let path: AnyObject
    }

    /// Builds an XCTest pointer-event record without synthesizing it, so the caller can
    /// dispatch the (blocking) synthesis and observe the app while the touch is down.
    /// Returns nil if the private synthesis API is unavailable.
    static func makeGestureRecord(
        named name: String,
        gesture: PointerGesture,
        targetProcessID: Int32
    ) -> GestureRecord? {
        guard let messageSend = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"),
              let pathClass = NSClassFromString("XCPointerEventPath"),
              let recordClass = NSClassFromString("XCSynthesizedEventRecord") else {
            return nil
        }

        typealias AllocateMessage = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>
        typealias PointInitializerMessage = @convention(c) (
            AnyObject, Selector, CGPoint, TimeInterval
        ) -> Unmanaged<AnyObject>
        typealias ObjectInitializerMessage = @convention(c) (
            AnyObject, Selector, AnyObject
        ) -> Unmanaged<AnyObject>
        typealias DoubleMessage = @convention(c) (AnyObject, Selector, TimeInterval) -> Void
        typealias PointDoubleMessage = @convention(c) (
            AnyObject, Selector, CGPoint, TimeInterval
        ) -> Void
        typealias ObjectMessage = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        typealias IntegerMessage = @convention(c) (AnyObject, Selector, Int64) -> Void

        let allocate = unsafeBitCast(messageSend, to: AllocateMessage.self)
        let initializePath = unsafeBitCast(messageSend, to: PointInitializerMessage.self)
        let initializeRecord = unsafeBitCast(messageSend, to: ObjectInitializerMessage.self)
        let sendDouble = unsafeBitCast(messageSend, to: DoubleMessage.self)
        let sendPointDouble = unsafeBitCast(messageSend, to: PointDoubleMessage.self)
        let sendObject = unsafeBitCast(messageSend, to: ObjectMessage.self)
        let sendInteger = unsafeBitCast(messageSend, to: IntegerMessage.self)

        // takeUnretainedValue throughout: `init` consumes the +1 from `alloc`, so taking
        // that +1 as well would over-release the object once these temporaries die.
        // Over-retaining instead leaks one object per gesture, which a test can afford.
        let path = initializePath(
            allocate(pathClass, NSSelectorFromString("alloc")).takeUnretainedValue(),
            NSSelectorFromString("initForTouchAtPoint:offset:"),
            gesture.start,
            0
        ).takeUnretainedValue()
        sendDouble(path, NSSelectorFromString("pressDownAtOffset:"), 0)
        for move in gesture.moves {
            sendPointDouble(
                path,
                NSSelectorFromString("moveToPoint:atOffset:"),
                move.point,
                move.offset
            )
        }
        sendDouble(path, NSSelectorFromString("liftUpAtOffset:"), gesture.liftOffset)

        let record = initializeRecord(
            allocate(recordClass, NSSelectorFromString("alloc")).takeUnretainedValue(),
            NSSelectorFromString("initWithName:"),
            name as NSString
        ).takeUnretainedValue()
        sendInteger(
            record,
            NSSelectorFromString("setTargetProcessID:"),
            Int64(targetProcessID)
        )
        sendObject(record, NSSelectorFromString("addPointerEventPath:"), path)
        return GestureRecord(record: record, path: path)
    }

    /// Blocks for the full duration of the gesture. Safe to call off the main thread so the
    /// test can query the app mid-gesture.
    nonisolated static func synthesize(_ record: GestureRecord) -> Bool {
        guard let messageSend = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend") else {
            return false
        }
        typealias SynthesizeMessage = @convention(c) (
            AnyObject, Selector, UnsafeMutablePointer<AnyObject?>?
        ) -> Bool
        let synthesize = unsafeBitCast(messageSend, to: SynthesizeMessage.self)
        var error: AnyObject?
        return synthesize(
            record.record,
            NSSelectorFromString("synthesizeWithError:"),
            &error
        )
    }

    /// Draws a multi-segment stroke — something `press(thenDragTo:)` cannot express — and holds
    /// still at the end long enough to trigger the dwell snap. Blocks until the pen lifts.
    @discardableResult
    static func drawStroke(
        in app: XCUIApplication,
        window: XCUIElement,
        through windowPoints: [CGPoint],
        holdDuration: TimeInterval = 1.2
    ) -> Bool {
        guard windowPoints.count >= 2 else { return false }

        // Points are window-relative, so they are offsets from the window's origin — the same
        // convention `boxSelect` uses. Subtracting the window's own position here would cancel
        // the origin back out and treat them as absolute screen points.
        let windowOrigin = window.coordinate(withNormalizedOffset: .zero)
        let screenPoints = windowPoints.map { windowPoint in
            windowOrigin
                .withOffset(CGVector(dx: windowPoint.x, dy: windowPoint.y))
                .screenPoint
        }

        // Densify so the recognizer sees a stroke rather than a handful of corners.
        let stepLength: CGFloat = 8
        let stepInterval: TimeInterval = 0.02
        var moves: [(point: CGPoint, offset: TimeInterval)] = []
        var offset: TimeInterval = 0
        for (start, end) in zip(screenPoints, screenPoints.dropFirst()) {
            let length = hypot(end.x - start.x, end.y - start.y)
            let steps = max(1, Int(ceil(length / stepLength)))
            for step in 1...steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                offset += stepInterval
                moves.append(
                    (
                        point: CGPoint(
                            x: start.x + (end.x - start.x) * fraction,
                            y: start.y + (end.y - start.y) * fraction
                        ),
                        offset: offset
                    )
                )
            }
        }

        // Repeating the last point keeps XCTest from interpolating across the hold.
        let holdInterval: TimeInterval = 0.05
        let holdSamples = max(1, Int((holdDuration / holdInterval).rounded()))
        guard let last = screenPoints.last else { return false }
        for _ in 1...holdSamples {
            offset += holdInterval
            moves.append((point: last, offset: offset))
        }

        guard let record = makeGestureRecord(
            named: "Shape stroke",
            gesture: PointerGesture(
                start: screenPoints[0],
                moves: moves,
                liftOffset: offset + holdInterval
            ),
            targetProcessID: processID(of: app)
        ) else {
            return false
        }
        return synthesize(record)
    }

    /// Boxed-selection drag around a rectangle of window points.
    static func boxSelect(in app: XCUIApplication, window: XCUIElement, around rect: CGRect) {
        selectTool("Select", in: app)
        selectTool("Box", in: app)
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: rect.minX, dy: rect.minY))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: rect.maxX, dy: rect.maxY))
            )
    }

    static func processID(of app: XCUIApplication) -> Int32 {
        guard let messageSend = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend") else { return 0 }
        typealias IntegerReturnMessage = @convention(c) (AnyObject, Selector) -> Int32
        let readInteger = unsafeBitCast(messageSend, to: IntegerReturnMessage.self)
        return readInteger(app, NSSelectorFromString("processID"))
    }

    static func openSiteNotes(in app: XCUIApplication) {
        let card = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Site notes'")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Site notes card not found")
        card.tap()
    }

    static func preparePersistedLineShapeForPencilOnlyRelaunch(
        using testCase: XCTestCase
    ) -> (
        app: XCUIApplication,
        window: XCUIElement,
        shapeMiddle: XCUICoordinate
    ) {
        let app = XCUIApplication()
        app.launch()

        openSiteNotes(in: app)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window not found")
        clearShapeDrawingArea(
            in: app,
            window: window,
            selectionStart: CGVector(dx: 0.22, dy: 0.38),
            selectionEnd: CGVector(dx: 0.80, dy: 0.76)
        )
        selectTool("Pen", in: app)

        let shapeCountElement = app.otherElements["vellum-shape-element-count"]
        XCTAssertTrue(
            shapeCountElement.waitForExistence(timeout: 10),
            "shape count accessibility element not found"
        )
        let shapeCountBefore = shapeCount(of: shapeCountElement)

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

        let created = testCase.expectation(
            for: NSPredicate(format: "value == %@", String(shapeCountBefore + 1)),
            evaluatedWith: shapeCountElement
        )
        testCase.wait(for: [created], timeout: 5)

        app.terminate()
        app.launchArguments = ["-vellum-force-pencil-only"]
        app.launch()

        openSiteNotes(in: app)

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

    static func selectTool(
        _ name: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // `exists` does not wait. Called right after entering a note the toolbar may not be in
        // the accessibility tree yet, and skipping the expand tap leaves every tool unreachable.
        // The collapse toggle is the one control the toolbar renders in both states (labelled
        // "Expand toolbar" only while collapsed), so waiting for either label proves the toolbar
        // rendered without paying a timeout on the common already-expanded path.
        let toolbarToggle = app.buttons.matching(
            NSPredicate(
                format: "label == 'Expand toolbar' OR label == 'Collapse toolbar'"
            )
        ).firstMatch
        _ = toolbarToggle.waitForExistence(timeout: 5)

        let expandToolbar = app.buttons["Expand toolbar"]
        if expandToolbar.exists {
            expandToolbar.tap()
        }

        let tool = app.buttons[name]
        XCTAssertTrue(
            tool.waitForExistence(timeout: 5),
            "\(name) tool not found",
            file: file,
            line: line
        )
        tool.tap()
    }

    static func clearShapeDrawingArea(
        in app: XCUIApplication,
        window: XCUIElement,
        selectionStart: CGVector,
        selectionEnd: CGVector
    ) {
        selectTool("Select", in: app)
        selectTool("Box", in: app)

        window.coordinate(withNormalizedOffset: selectionStart).press(
            forDuration: 0.05,
            thenDragTo: window.coordinate(withNormalizedOffset: selectionEnd)
        )

        let deleteSelection = app.buttons["Delete selection"]
        if deleteSelection.waitForExistence(timeout: 1) {
            deleteSelection.tap()
        }
    }

    static func shapeCount(
        of element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int {
        if let value = element.value as? String, let count = Int(value) {
            return count
        }
        if let value = element.value as? NSNumber {
            return value.intValue
        }
        XCTFail(
            "shape count has unexpected value: \(String(describing: element.value))",
            file: file,
            line: line
        )
        return -1
    }

    static func accessibilityValue(
        of element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        guard let value = element.value as? String else {
            XCTFail(
                "shape vertex summary has unexpected value: "
                    + String(describing: element.value),
                file: file,
                line: line
            )
            return ""
        }
        return value
    }

    static func vertices(
        from summary: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [CGPoint] {
        summary.split(separator: ";").compactMap { encodedPoint in
            let coordinates = encodedPoint.split(separator: ",")
            guard coordinates.count == 2,
                  let x = Double(coordinates[0]),
                  let y = Double(coordinates[1]) else {
                XCTFail(
                    "invalid shape vertex summary: \(summary)",
                    file: file,
                    line: line
                )
                return nil
            }
            return CGPoint(x: x, y: y)
        }
    }
}
