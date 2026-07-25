import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class ShapeSnapOrchestrationTests: XCTestCase {
    func testMidStrokeSnapStripsOnlyNewMatchingStrokeAndUndoRedoAreAtomic() async {
        let harness = makeHarness(policy: .snapMidStroke)
        let unrelatedStroke = makeStroke(
            from: CGPoint(x: 40, y: 520),
            to: CGPoint(x: 160, y: 520)
        )
        harness.canvasView.drawing = PKDrawing(strokes: [unrelatedStroke])
        let points = recognizableLinePoints()
        XCTAssertNotNil(ShapeRecognizer.recognize(points: points))

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()

        // Model the PencilKit race that can append a cancelled partial stroke
        // after drawingGestureRecognizer is disabled but before the deferred strip.
        let matchingStroke = makeStroke(from: points[0], to: points[points.count - 1])
        harness.canvasView.drawing = PKDrawing(
            strokes: [unrelatedStroke, matchingStroke]
        )
        await drainMainQueue()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        assertBounds(
            harness.canvasView.drawing.strokes[0].renderBounds,
            equalTo: unrelatedStroke.renderBounds
        )
        XCTAssertEqual(shapeElements(in: harness.store).count, 1)
        XCTAssertFalse(harness.undoManager.canUndo)

        harness.controller.strokeEnded(cancelled: false)

        XCTAssertEqual(harness.undoManager.undoActionName, "Draw Shape")
        XCTAssertTrue(harness.canvasView.drawingGestureRecognizer.isEnabled)

        harness.undoManager.undo()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 2)
        XCTAssertTrue(harness.store.elements.isEmpty)
        XCTAssertTrue(harness.undoManager.canRedo)

        harness.undoManager.redo()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        assertBounds(
            harness.canvasView.drawing.strokes[0].renderBounds,
            equalTo: unrelatedStroke.renderBounds
        )
        XCTAssertEqual(shapeElements(in: harness.store).count, 1)
    }

    func testSnapOnLiftReplacesOnlyLastStrokeWhenCaptureBoundsMatch() async {
        let harness = makeHarness(policy: .snapOnLift)
        let unrelatedStroke = makeStroke(
            from: CGPoint(x: 40, y: 520),
            to: CGPoint(x: 160, y: 520)
        )
        harness.canvasView.drawing = PKDrawing(strokes: [unrelatedStroke])
        let points = recognizableLinePoints()

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()

        XCTAssertNotNil(harness.controller.pendingShapeToCommitOnLift)
        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        XCTAssertTrue(harness.store.elements.isEmpty)

        let matchingStroke = makeStroke(from: points[0], to: points[points.count - 1])
        harness.canvasView.drawing = PKDrawing(
            strokes: [unrelatedStroke, matchingStroke]
        )
        harness.controller.strokeEnded(cancelled: false)
        await drainMainQueue()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        assertBounds(
            harness.canvasView.drawing.strokes[0].renderBounds,
            equalTo: unrelatedStroke.renderBounds
        )
        XCTAssertEqual(shapeElements(in: harness.store).count, 1)
        XCTAssertEqual(harness.undoManager.undoActionName, "Draw Shape")
    }

    func testSnapOnLiftKeepsLastStrokeWhenCaptureBoundsDoNotMatch() async {
        let harness = makeHarness(policy: .snapOnLift)
        let points = recognizableLinePoints()

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()

        let mismatchedStroke = makeStroke(
            from: CGPoint(x: 40, y: 520),
            to: CGPoint(x: 160, y: 520)
        )
        harness.canvasView.drawing = PKDrawing(strokes: [mismatchedStroke])
        harness.controller.strokeEnded(cancelled: false)
        await drainMainQueue()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        assertBounds(
            harness.canvasView.drawing.strokes[0].renderBounds,
            equalTo: mismatchedStroke.renderBounds
        )
        XCTAssertEqual(shapeElements(in: harness.store).count, 1)
    }

    func testRecognizerNilLeavesDrawingElementsAndUndoStateUnchanged() {
        let harness = makeHarness(policy: .snapMidStroke)
        let existingStroke = makeStroke(
            from: CGPoint(x: 40, y: 520),
            to: CGPoint(x: 160, y: 520)
        )
        let existingElement = makeExistingElement()
        harness.canvasView.drawing = PKDrawing(strokes: [existingStroke])
        harness.store.hydrate([existingElement])
        let drawingBefore = harness.canvasView.drawing.dataRepresentation()
        let elementsBefore = harness.store.elements
        let rejectedPoints = [
            CGPoint(x: 100, y: 200),
            CGPoint(x: 101, y: 200),
            CGPoint(x: 102, y: 201),
        ]
        XCTAssertNil(ShapeRecognizer.recognize(points: rejectedPoints))

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(
                rejectedPoints,
                zoomScale: harness.canvasView.zoomScale
            )
        )
        harness.controller.dwellFired()

        XCTAssertEqual(
            harness.canvasView.drawing.dataRepresentation(),
            drawingBefore
        )
        XCTAssertEqual(harness.store.elements, elementsBefore)
        XCTAssertFalse(harness.undoManager.canUndo)
    }

    func testStylingMirrorsInkToolFactoryAndClampsWidths() {
        let markerColor = CodableColor(
            red: 0.2,
            green: 0.4,
            blue: 0.6,
            alpha: 0.2
        )
        let marker = InkToolConfig(
            style: .marker,
            color: markerColor,
            width: 500
        )
        let styledMarkerColor = ShapeSnapController.styledStrokeColor(for: marker)
        XCTAssertEqual(styledMarkerColor.red, markerColor.red)
        XCTAssertEqual(styledMarkerColor.green, markerColor.green)
        XCTAssertEqual(styledMarkerColor.blue, markerColor.blue)
        XCTAssertEqual(styledMarkerColor.alpha, 0.55)
        XCTAssertEqual(
            ShapeSnapController.styledStrokeWidth(for: marker),
            NoteToolFactory.widthRange(for: .marker).upperBound
        )

        let pen = InkToolConfig(
            style: .pen,
            color: CodableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4),
            width: -100
        )
        XCTAssertEqual(
            ShapeSnapController.styledStrokeColor(for: pen),
            pen.color
        )
        XCTAssertEqual(
            ShapeSnapController.styledStrokeWidth(for: pen),
            NoteToolFactory.widthRange(for: .pen).lowerBound
        )
    }

    func testMidStrokeMarkerSnapStoresAlphaOverride() async {
        let marker = InkToolConfig(
            style: .marker,
            color: CodableColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 0.1),
            width: 12
        )
        let harness = makeHarness(policy: .snapMidStroke, inkConfig: marker)
        let points = recognizableLinePoints()

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()
        await drainMainQueue()
        harness.controller.strokeEnded(cancelled: false)

        guard let element = harness.store.elements.first,
              case .shape(let content) = element.content else {
            return XCTFail("Expected a snapped shape element.")
        }
        XCTAssertEqual(content.strokeColor.alpha, 0.55)
    }

    // Regression test for a data-loss race: performMidStrokeSnap resolves
    // its inputs (capture bbox, ink config, elements store) on the runloop
    // turn where drawingGestureRecognizer is disabled, so a pen lift racing
    // ahead of that deferred commit must NOT find those inputs already
    // cleared by strokeEnded -> resetStrokeState. Before the fix this test
    // failed because the async block re-read self.captureBoundingBox()
    // (nil after reset) and silently bailed, losing the stroke.
    func testPenLiftImmediatelyAfterDwellStillCommitsTheShape() async {
        let harness = makeHarness(policy: .snapMidStroke)
        let points = recognizableLinePoints()

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()

        // Simulate the pen lifting on the very next runloop turn, before the
        // deferred `DispatchQueue.main.async` commit inside
        // `performMidStrokeSnap` has had a chance to run.
        harness.controller.strokeEnded(cancelled: false)

        await drainMainQueue()

        XCTAssertEqual(shapeElements(in: harness.store).count, 1)
        XCTAssertEqual(harness.undoManager.undoActionName, "Draw Shape")
        XCTAssertTrue(harness.canvasView.drawingGestureRecognizer.isEnabled)
    }

    func testLineSnapAdjustsFreeEndpointAndUndoesFinalGestureAtomically() async throws {
        let harness = makeHarness(policy: .snapMidStroke)
        let unrelatedStroke = makeStroke(
            from: CGPoint(x: 40, y: 520),
            to: CGPoint(x: 160, y: 520)
        )
        harness.canvasView.drawing = PKDrawing(strokes: [unrelatedStroke])
        let points = recognizableLinePoints()

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()

        let matchingStroke = makeStroke(from: points[0], to: points[points.count - 1])
        harness.canvasView.drawing = PKDrawing(
            strokes: [unrelatedStroke, matchingStroke]
        )
        let strokesBeforeSnap = harness.canvasView.drawing.strokes
        await drainMainQueue()

        let initialElement = try XCTUnwrap(shapeElements(in: harness.store).first)
        let initialVertices = shapeVertices(of: initialElement)
        XCTAssertEqual(initialVertices.count, 2)
        let currentPenPosition = try XCTUnwrap(points.last)
        let pivot = try XCTUnwrap(
            initialVertices.max {
                distance($0, currentPenPosition) < distance($1, currentPenPosition)
            }
        )

        harness.canvasView.drawingGestureRecognizer.isEnabled = true
        let diagonalEndpoint = CGPoint(x: pivot.x + 150, y: pivot.y + 80)
        harness.controller.strokeContinued(
            points: [
                TimedPoint(
                    location: diagonalEndpoint,
                    timestamp: 2
                ),
            ]
        )

        XCTAssertFalse(harness.canvasView.drawingGestureRecognizer.isEnabled)
        let diagonalElement = try XCTUnwrap(shapeElements(in: harness.store).first)
        let diagonalVertices = shapeVertices(of: diagonalElement)
        assertLineVertices(
            diagonalVertices,
            pivot: pivot,
            endpoint: diagonalEndpoint
        )

        let nearHorizontalEndpoint = CGPoint(x: pivot.x + 190, y: pivot.y + 3)
        harness.controller.strokeContinued(
            points: [
                TimedPoint(
                    location: nearHorizontalEndpoint,
                    timestamp: 2.1
                ),
            ]
        )

        let finalElement = try XCTUnwrap(shapeElements(in: harness.store).first)
        let finalVertices = shapeVertices(of: finalElement)
        let finalFreeEndpoint = try XCTUnwrap(
            finalVertices.first(where: { distance($0, pivot) > 0.001 })
        )
        XCTAssertEqual(finalFreeEndpoint.x, nearHorizontalEndpoint.x, accuracy: 0.001)
        XCTAssertEqual(finalFreeEndpoint.y, pivot.y, accuracy: 0.001)
        XCTAssertFalse(harness.undoManager.canUndo)

        let strokesAfterAdjustment = harness.canvasView.drawing.strokes
        harness.controller.strokeEnded(cancelled: false)

        XCTAssertTrue(harness.canvasView.drawingGestureRecognizer.isEnabled)
        XCTAssertEqual(harness.undoManager.undoActionName, "Draw Shape")
        XCTAssertTrue(harness.undoManager.canUndo)

        harness.undoManager.undo()

        // Undo round-trips through PKDrawing(data:), which does not guarantee a
        // byte-identical dataRepresentation(). Compare count and renderBounds instead.
        let undoneStrokes = harness.canvasView.drawing.strokes
        XCTAssertEqual(undoneStrokes.count, strokesBeforeSnap.count)
        for (actual, expected) in zip(undoneStrokes, strokesBeforeSnap) {
            assertBounds(actual.renderBounds, equalTo: expected.renderBounds)
        }
        XCTAssertTrue(harness.store.elements.isEmpty)
        XCTAssertFalse(harness.undoManager.canUndo)
        XCTAssertTrue(harness.undoManager.canRedo)

        harness.undoManager.redo()

        // Redo also round-trips through PKDrawing(data:), so compare stroke count
        // and per-stroke renderBounds rather than dataRepresentation() bytes.
        let redoneStrokes = harness.canvasView.drawing.strokes
        XCTAssertEqual(redoneStrokes.count, strokesAfterAdjustment.count)
        for (actual, expected) in zip(redoneStrokes, strokesAfterAdjustment) {
            assertBounds(actual.renderBounds, equalTo: expected.renderBounds)
        }
        XCTAssertEqual(shapeElements(in: harness.store), [finalElement])
        let redoneElement = try XCTUnwrap(shapeElements(in: harness.store).first)
        let redoneVertices = shapeVertices(of: redoneElement)
        assertLineVertices(
            redoneVertices,
            pivot: pivot,
            endpoint: CGPoint(x: nearHorizontalEndpoint.x, y: pivot.y)
        )
    }

    func testNonLineSnapCommitsImmediatelyAndIgnoresFurtherSamples() async throws {
        let harness = makeHarness(policy: .snapMidStroke)
        let points = recognizableRectanglePoints()
        guard case .polyline(let vertices, true) = ShapeRecognizer.recognize(points: points) else {
            return XCTFail("Expected the fixture to recognize as a closed polyline.")
        }
        XCTAssertEqual(vertices.count, 4)

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()
        await drainMainQueue()

        let snappedElement = try XCTUnwrap(shapeElements(in: harness.store).first)
        XCTAssertEqual(harness.undoManager.undoActionName, "Draw Shape")
        XCTAssertTrue(harness.undoManager.canUndo)
        XCTAssertTrue(harness.canvasView.drawingGestureRecognizer.isEnabled)

        harness.controller.strokeContinued(
            points: [
                TimedPoint(
                    location: CGPoint(x: 500, y: 500),
                    timestamp: 4
                ),
            ]
        )

        XCTAssertEqual(shapeElements(in: harness.store), [snappedElement])
        XCTAssertTrue(harness.canvasView.drawingGestureRecognizer.isEnabled)
        harness.controller.strokeEnded(cancelled: false)
        XCTAssertEqual(harness.undoManager.undoActionName, "Draw Shape")
    }

    private func makeHarness(
        policy: ShapeSnapPolicy,
        inkConfig: InkToolConfig = ToolPreferences.default.pen
    ) -> Harness {
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { _ in },
            onViewportChanged: nil
        )
        let canvasView = PKCanvasView()
        canvasView.minimumZoomScale = 0.1
        canvasView.maximumZoomScale = 10
        canvasView.zoomScale = 1
        canvasView.delegate = coordinator
        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView
        let undoManager = UndoManager()
        let store = CanvasElementsStore()
        store.canvasReference = canvasReference
        store.undoManagerOverride = undoManager
        let controller = ShapeSnapController(policy: policy)
        controller.canvasReference = canvasReference
        controller.elementsStore = store
        controller.isEnabled = true
        controller.activeInkConfig = inkConfig
        controller.isDrawingEnabled = true
        return Harness(
            canvasView: canvasView,
            coordinator: coordinator,
            store: store,
            undoManager: undoManager,
            controller: controller
        )
    }

    private func recognizableLinePoints() -> [CGPoint] {
        (0...40).map { index in
            CGPoint(
                x: 100 + CGFloat(index) * 3,
                y: 200
            )
        }
    }

    private func recognizableRectanglePoints() -> [CGPoint] {
        let vertices = [
            CGPoint(x: 100, y: 180),
            CGPoint(x: 220, y: 180),
            CGPoint(x: 220, y: 280),
            CGPoint(x: 100, y: 280),
            CGPoint(x: 100, y: 180),
        ]
        var points = [vertices[0]]
        for (start, end) in zip(vertices, vertices.dropFirst()) {
            let length = distance(start, end)
            let segmentCount = max(1, Int(ceil(length / 3)))
            for index in 1...segmentCount {
                let fraction = CGFloat(index) / CGFloat(segmentCount)
                points.append(
                    CGPoint(
                        x: start.x + (end.x - start.x) * fraction,
                        y: start.y + (end.y - start.y) * fraction
                    )
                )
            }
        }
        return points
    }

    private func timedPoints(
        _ points: [CGPoint],
        zoomScale: CGFloat
    ) -> [TimedPoint] {
        points.enumerated().map { index, point in
            TimedPoint(
                location: CGPoint(
                    x: point.x * zoomScale,
                    y: point.y * zoomScale
                ),
                timestamp: TimeInterval(index) * 0.01
            )
        }
    }

    private func makeStroke(from start: CGPoint, to end: CGPoint) -> PKStroke {
        let points = [
            PKStrokePoint(
                location: start,
                timeOffset: 0,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: end,
                timeOffset: 0.1,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
        ]
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
    }

    private func makeExistingElement() -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Existing",
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: CanvasRect(x: 10, y: 20, width: 100, height: 40)
        )
    }

    private func shapeElements(in store: CanvasElementsStore) -> [CanvasElement] {
        store.elements.filter {
            if case .shape = $0.content {
                return true
            }
            return false
        }
    }

    private func shapeVertices(of element: CanvasElement) -> [CGPoint] {
        guard case .shape(let content) = element.content else {
            XCTFail("Expected a shape element.")
            return []
        }
        return ShapeVertexEditor.absoluteVertices(
            content: content,
            frame: element.frame,
            rotation: element.rotation
        )
    }

    private func assertLineVertices(
        _ vertices: [CGPoint],
        pivot: CGPoint,
        endpoint: CGPoint,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(vertices.count, 2, file: file, line: line)
        guard vertices.count == 2 else { return }
        XCTAssertTrue(
            vertices.contains { distance($0, pivot) < 0.001 },
            "Pivot moved during line adjustment.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            vertices.contains { distance($0, endpoint) < 0.001 },
            "Free endpoint did not reach the expected point.",
            file: file,
            line: line
        )
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }

    private func assertBounds(
        _ actual: CGRect,
        equalTo expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, file: file, line: line)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private struct Harness {
        let canvasView: PKCanvasView
        let coordinator: PencilCanvasView.Coordinator
        let store: CanvasElementsStore
        let undoManager: UndoManager
        let controller: ShapeSnapController
    }
}
