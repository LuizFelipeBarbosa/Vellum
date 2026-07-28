import XCTest

@MainActor
final class ShapeVertexEditFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDraggingSelectedShapeVertexChangesGeometry() {
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

        let snapped = expectation(
            for: NSPredicate(
                format: "value == %@",
                String(shapeCountBefore + 1)
            ),
            evaluatedWith: shapeCountElement
        )
        wait(for: [snapped], timeout: 5)

        selectBoxTool(in: app)
        let selectionStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.26, dy: 0.54)
        )
        let selectionEnd = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.62, dy: 0.62)
        )
        selectionStart.press(forDuration: 0.05, thenDragTo: selectionEnd)

        let vertexHandles = app.otherElements["vellum-shape-vertex-handles"]
        XCTAssertTrue(
            vertexHandles.waitForExistence(timeout: 5),
            "shape vertex handles did not appear after boxed selection"
        )
        let verticesBefore = accessibilityValue(of: vertexHandles)
        XCTAssertFalse(verticesBefore.isEmpty, "selected shape vertex summary is empty")
        let pointsBefore = vertices(from: verticesBefore)
        guard pointsBefore.count >= 2 else {
            XCTFail("selected shape exposes fewer than two vertices")
            return
        }

        let firstVertex = app.descendants(matching: .any)
            .matching(identifier: "vellum-shape-vertex-handle-0")
            .firstMatch
        XCTAssertTrue(
            firstVertex.waitForExistence(timeout: 5),
            "first shape vertex handle not found"
        )
        let vertexStart = firstVertex.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        vertexStart.press(
            forDuration: 0.05,
            thenDragTo: vertexStart.withOffset(CGVector(dx: -44, dy: -36))
        )

        let reshaped = expectation(
            for: NSPredicate(format: "value != %@", verticesBefore),
            evaluatedWith: vertexHandles
        )
        wait(for: [reshaped], timeout: 5)
        let verticesAfter = accessibilityValue(of: vertexHandles)
        XCTAssertNotEqual(
            verticesAfter,
            verticesBefore,
            "dragging a vertex handle did not change the shape geometry"
        )

        let pointsAfter = vertices(from: verticesAfter)
        guard pointsAfter.count == pointsBefore.count else {
            XCTFail("shape vertex count changed during a single-vertex drag")
            return
        }
        XCTAssertGreaterThan(
            hypot(
                pointsAfter[0].x - pointsBefore[0].x,
                pointsAfter[0].y - pointsBefore[0].y
            ),
            10,
            "the dragged vertex did not move"
        )
        XCTAssertEqual(pointsAfter[1].x, pointsBefore[1].x, accuracy: 1)
        XCTAssertEqual(pointsAfter[1].y, pointsBefore[1].y, accuracy: 1)
    }

    private func openSiteNotes(in app: XCUIApplication) {
        let card = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Site notes'")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Site notes card not found")
        card.tap()
    }

    private func clearShapeDrawingArea(
        in app: XCUIApplication,
        window: XCUIElement
    ) {
        selectBoxTool(in: app)

        let selectionStart = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.26, dy: 0.54)
        )
        let selectionEnd = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.62, dy: 0.62)
        )
        selectionStart.press(forDuration: 0.05, thenDragTo: selectionEnd)

        let deleteSelection = app.buttons["Delete selection"]
        if deleteSelection.waitForExistence(timeout: 1) {
            deleteSelection.tap()
        }
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
    }

    private func selectBoxTool(in app: XCUIApplication) {
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
}
