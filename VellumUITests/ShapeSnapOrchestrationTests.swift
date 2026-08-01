import Foundation
import PencilKit
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class ShapeSnapOrchestrationTests: XCTestCase {
    func testMidStrokeSnapStripsOnlyNewMatchingStrokeAndUndoRedoAreAtomic() async {
        let harness = makeHarness(policy: .snapMidStroke)
        let unrelatedStroke = CanvasFixtures.makeStroke(
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
        let matchingStroke = CanvasFixtures.makeStroke(from: points[0], to: points[points.count - 1])
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
        let unrelatedStroke = CanvasFixtures.makeStroke(
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

        let matchingStroke = CanvasFixtures.makeStroke(from: points[0], to: points[points.count - 1])
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

    // A stroke that lands nowhere near the captured points is not the ink this snap
    // recognized, so the commit has nothing to replace. Inserting the shape anyway would
    // leave both on the page — the sketch plus a perfect copy of it — so the snap is
    // dropped instead and the canvas keeps exactly what the user drew.
    func testSnapOnLiftInsertsNoShapeWhenCaptureBoundsDoNotMatch() async {
        let harness = makeHarness(policy: .snapOnLift)
        let points = recognizableLinePoints()

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()

        let mismatchedStroke = CanvasFixtures.makeStroke(
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
        XCTAssertTrue(
            shapeElements(in: harness.store).isEmpty,
            "a shape with no ink to replace would just duplicate the geometry"
        )
        XCTAssertFalse(harness.undoManager.canUndo)
    }

    // Regression test for a data-loss bug: PencilKit does not promise to have appended
    // the lifted stroke by the time the deferred commit runs, and when it has not, the
    // last stroke on the canvas is the user's PREVIOUS one. Removing that would destroy
    // ink the snap never touched — the worse because snap-on-lift is the fallback policy
    // people reach for when mid-stroke snapping misbehaves.
    func testSnapOnLiftKeepsThePreviousStrokeWhenTheInkHasNotLandedYet() async {
        let harness = makeHarness(policy: .snapOnLift)
        let points = recognizableLinePoints()
        // An older sketch sitting right where the shape is being drawn: its bounds are
        // inside the capture box, so only the stroke count can tell the two apart.
        let existingStroke = CanvasFixtures.makeStroke(from: points[0], to: points[points.count - 1])
        harness.canvasView.drawing = PKDrawing(strokes: [existingStroke])

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()

        // The pen lifts, but PencilKit has not committed the new stroke yet.
        harness.controller.strokeEnded(cancelled: false)
        await drainMainQueue()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        assertBounds(
            harness.canvasView.drawing.strokes[0].renderBounds,
            equalTo: existingStroke.renderBounds
        )
        XCTAssertTrue(
            shapeElements(in: harness.store).isEmpty,
            "with no ink of its own to replace, the snap has to stand down"
        )
        XCTAssertFalse(harness.undoManager.canUndo)
    }

    func testSnapOnLiftReplacesOnlyTheInkDrawnOverAnOlderSketch() async {
        let harness = makeHarness(policy: .snapOnLift)
        let points = recognizableLinePoints()
        let existingStroke = CanvasFixtures.makeStroke(from: points[0], to: points[points.count - 1])
        harness.canvasView.drawing = PKDrawing(strokes: [existingStroke])

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()

        // Same geometry as the older stroke: the two are only distinguishable by order.
        let matchingStroke = CanvasFixtures.makeStroke(from: points[0], to: points[points.count - 1])
        harness.canvasView.drawing = PKDrawing(
            strokes: [existingStroke, matchingStroke]
        )
        harness.controller.strokeEnded(cancelled: false)
        await drainMainQueue()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        assertBounds(
            harness.canvasView.drawing.strokes[0].renderBounds,
            equalTo: existingStroke.renderBounds
        )
        XCTAssertEqual(shapeElements(in: harness.store).count, 1)
        XCTAssertEqual(harness.undoManager.undoActionName, "Draw Shape")
    }

    // Regression test for the same data-loss race as
    // `testPenLiftImmediatelyAfterDwellStillCommitsTheShape`, on the snap-on-lift
    // path: the deferred commit used to re-read `activeInkConfig` / `elementsStore`,
    // so a tool switch or a teardown landing before it ran dropped the shape.
    func testSnapOnLiftCommitsWithTheLiftedToolEvenIfTheToolChangesFirst() async throws {
        let marker = InkToolConfig(
            style: .marker,
            color: CodableColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 0.1),
            width: 12
        )
        let harness = makeHarness(policy: .snapOnLift, inkConfig: marker)
        let points = recognizableLinePoints()

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()

        let matchingStroke = CanvasFixtures.makeStroke(from: points[0], to: points[points.count - 1])
        harness.canvasView.drawing = PKDrawing(strokes: [matchingStroke])
        harness.controller.strokeEnded(cancelled: false)

        harness.controller.activeInkConfig = nil
        harness.controller.elementsStore = nil
        await drainMainQueue()

        XCTAssertTrue(
            harness.canvasView.drawing.strokes.isEmpty,
            "the inked stroke still has to be replaced by the shape"
        )
        let element = try XCTUnwrap(shapeElements(in: harness.store).first)
        guard case .shape(let content) = element.content else {
            return XCTFail("Expected a snapped shape element.")
        }
        XCTAssertEqual(
            content.strokeColor.alpha,
            0.55,
            "the commit must use the ink config captured at lift, not the current one"
        )
        XCTAssertEqual(harness.undoManager.undoActionName, "Draw Shape")
    }

    // The recognizer promises one end notification per stroke, but the surface also
    // ends the stroke when it is torn down, which can land right after a real lift.
    // A second notification must not commit the pending shape twice.
    func testASecondStrokeEndedCommitsNothingFurther() async {
        let harness = makeHarness(policy: .snapOnLift)
        let points = recognizableLinePoints()

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()

        let matchingStroke = CanvasFixtures.makeStroke(from: points[0], to: points[points.count - 1])
        harness.canvasView.drawing = PKDrawing(strokes: [matchingStroke])
        harness.controller.strokeEnded(cancelled: false)
        harness.controller.strokeEnded(cancelled: true)
        await drainMainQueue()

        XCTAssertEqual(shapeElements(in: harness.store).count, 1)
        XCTAssertTrue(harness.canvasView.drawing.strokes.isEmpty)
        XCTAssertEqual(harness.undoManager.undoActionName, "Draw Shape")
    }

    func testRecognizerNilLeavesDrawingElementsAndUndoStateUnchanged() {
        let harness = makeHarness(policy: .snapMidStroke)
        let existingStroke = CanvasFixtures.makeStroke(
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
        let unrelatedStroke = CanvasFixtures.makeStroke(
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

        let matchingStroke = CanvasFixtures.makeStroke(from: points[0], to: points[points.count - 1])
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

    // Regression test for a latched exemption: `survivesNextToolChange` is set by a shape tap
    // and spent by the tool change that same tap triggers. Dropping the selection has to spend
    // it too, or an unrelated later tool change inherits it and silently keeps a selection.
    func testClearingTheSelectionSpendsTheToolChangeExemption() {
        let harness = makeSelectionHarness()
        let shape = makeOpenPolylineElement()
        harness.store.hydrate([shape])

        harness.controller.selectElement(id: shape.id, survivesNextToolChange: true)
        harness.controller.clearSelection()

        // A selection made by lassoing carries no exemption of its own.
        harness.controller.beginCapture(at: CGPoint(x: 10, y: 10), mode: .boxed)
        harness.controller.extendCapture(to: CGPoint(x: 400, y: 400))
        harness.controller.endCapture()
        XCTAssertNotNil(harness.controller.selection)

        harness.controller.toolChanged()

        XCTAssertNil(harness.controller.selection)
        withExtendedLifetime(harness) {}
    }

    // The overlay's `activeVertexIndex` can outlive a gesture SwiftUI cancels, so both of its
    // recovery paths lean on the controller: a fresh handle may take over a drag still marked as
    // in flight, and ending a drag that is no longer running must be harmless. The @State latch
    // itself is only reachable through a real SwiftUI gesture, so it is not covered here.
    func testAVertexDragCanBeTakenOverByAnotherHandleAndEndedTwice() throws {
        let harness = makeSelectionHarness()
        let shape = makeOpenPolylineElement()
        harness.store.hydrate([shape])
        harness.controller.selectElement(id: shape.id)

        harness.controller.beginVertexDrag(elementID: shape.id, vertexIndex: 0)
        harness.controller.setVertexPosition(CGPoint(x: 60, y: 60))

        // The first handle never reported an end, so the second one has to rebind the drag.
        harness.controller.beginVertexDrag(elementID: shape.id, vertexIndex: 2)
        XCTAssertTrue(harness.controller.isVertexDragging)
        harness.controller.setVertexPosition(CGPoint(x: 300, y: 300))
        harness.controller.endVertexDrag()

        let edited = try XCTUnwrap(harness.store.elements.first)
        let vertices = shapeVertices(of: edited)
        XCTAssertEqual(vertices.count, 3)
        XCTAssertEqual(vertices[0].x, 60, accuracy: 0.001)
        XCTAssertEqual(vertices[0].y, 60, accuracy: 0.001)
        XCTAssertEqual(vertices[2].x, 300, accuracy: 0.001)
        XCTAssertEqual(vertices[2].y, 300, accuracy: 0.001)
        XCTAssertFalse(harness.controller.isVertexDragging)
        XCTAssertEqual(harness.undoManager.undoActionName, "Edit Shape")

        // What the overlay calls to release a drag it may or may not still own.
        harness.controller.endVertexDrag()

        XCTAssertEqual(harness.store.elements, [edited])
        XCTAssertFalse(harness.controller.isVertexDragging)
        withExtendedLifetime(harness) {}
    }

    private func makeSelectionHarness() -> SelectionHarness {
        let canvasView = PKCanvasView()
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { _ in },
            onViewportChanged: nil
        )
        canvasView.delegate = coordinator
        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView
        let undoManager = UndoManager()
        let store = CanvasElementsStore()
        store.canvasReference = canvasReference
        store.undoManagerOverride = undoManager
        let controller = CanvasSelectionController()
        controller.canvasReference = canvasReference
        controller.elementsStore = store
        return SelectionHarness(
            canvasView: canvasView,
            coordinator: coordinator,
            store: store,
            undoManager: undoManager,
            controller: controller
        )
    }

    private func makeOpenPolylineElement() -> CanvasElement {
        CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0),
                            CanvasPoint(x: 1, y: 0),
                            CanvasPoint(x: 1, y: 1),
                        ],
                        isClosed: false
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 4
                )
            ),
            frame: CanvasRect(x: 100, y: 100, width: 100, height: 100)
        )
    }

    func testStrokeBeyondCapturePointLimitAbandonsRecognition() async {
        let harness = makeHarness(policy: .snapMidStroke)
        harness.controller.strokeBegan()

        let filler = (0..<4_000).map { CGPoint(x: CGFloat($0 % 400), y: CGFloat($0 / 400)) }
        harness.controller.strokeContinued(points: timedPoints(filler, zoomScale: 1))
        XCTAssertEqual(
            harness.controller.capturedContentPoints.count,
            4_000,
            "a stroke under the cap should still be captured"
        )

        harness.controller.strokeContinued(
            points: timedPoints(Array(filler.prefix(200)), zoomScale: 1)
        )
        XCTAssertTrue(
            harness.controller.capturedContentPoints.isEmpty,
            "outgrowing the cap should drop the capture rather than trim its front"
        )

        // Recognition stays off for the rest of the stroke, even for a shape it would have taken.
        harness.controller.strokeContinued(
            points: timedPoints(recognizableLinePoints(), zoomScale: 1)
        )
        XCTAssertTrue(harness.controller.capturedContentPoints.isEmpty)

        harness.controller.dwellFired()
        await drainMainQueue()
        XCTAssertTrue(
            shapeElements(in: harness.store).isEmpty,
            "an abandoned capture must not snap a shape"
        )
        XCTAssertTrue(
            harness.canvasView.drawingGestureRecognizer.isEnabled,
            "giving up on recognition must leave PencilKit free to keep inking"
        )

        // The next stroke starts clean.
        harness.controller.strokeEnded(cancelled: false)
        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(recognizableLinePoints(), zoomScale: 1)
        )
        harness.controller.dwellFired()
        await drainMainQueue()
        XCTAssertEqual(
            shapeElements(in: harness.store).count,
            1,
            "the abandonment flag must not survive into the next stroke"
        )
    }

    func testRecognizerDisableWaitsForPenLift() {
        let harness = makeHarness(policy: .snapMidStroke)
        let coordinator = ShapeSnapSurface.Coordinator(controller: harness.controller)

        coordinator.syncInstallation()
        XCTAssertTrue(
            coordinator.recognizer.isEnabled,
            "an ink tool should switch the observer on"
        )

        coordinator.recognizer.onStrokeBegan?()
        harness.controller.isEnabled = false
        coordinator.syncInstallation()
        XCTAssertTrue(
            coordinator.recognizer.isEnabled,
            "disabling mid-stroke would cancel the touch and strand strokeEnded's teardown"
        )

        coordinator.recognizer.onStrokeEnded?(false)
        XCTAssertFalse(
            coordinator.recognizer.isEnabled,
            "the pen lift is where a pending disable takes effect"
        )
    }

    // `reset()` is the only signal for a stroke UIKit terminates without delivering
    // touchesEnded/touchesCancelled (the recognizer disabled or detached mid-touch),
    // so it has to report the end — exactly once, or the controller would commit an
    // already-committed live session a second time.
    func testGestureResetReportsAnUnfinishedStrokeExactlyOnce() {
        let recognizer = PenDwellObserverGestureRecognizer()
        recognizer.allowsDirectTouches = true
        var endedCalls: [Bool] = []
        recognizer.onStrokeEnded = { endedCalls.append($0) }
        let touch = StubTouch()
        let event = StubEvent()

        recognizer.touchesBegan([touch], with: event)
        recognizer.reset()

        XCTAssertEqual(endedCalls, [true], "an abandoned stroke has to be reported")

        recognizer.reset()

        XCTAssertEqual(endedCalls, [true], "a reported stroke must stay reported once")
    }

    // A normal lift already reports the end, and the `state = .failed` it performs can
    // make UIKit reset the recognizer right after — that reset must stay silent.
    func testALiftFollowedByAResetReportsTheStrokeEndOnlyOnce() {
        let recognizer = PenDwellObserverGestureRecognizer()
        recognizer.allowsDirectTouches = true
        var endedCalls: [Bool] = []
        recognizer.onStrokeEnded = { endedCalls.append($0) }
        let touch = StubTouch()
        let event = StubEvent()

        recognizer.touchesBegan([touch], with: event)
        recognizer.touchesEnded([touch], with: event)
        recognizer.reset()

        XCTAssertEqual(endedCalls, [false])
    }

    // The controller half of the same failure: if a stroke that opened a live line
    // adjustment never reports its end, the next stroke must not inherit the pivot and
    // rewrite that element, and PencilKit must get its drawing recognizer back.
    func testAStrokeThatNeverEndedDoesNotRedirectTheNextStroke() async throws {
        let harness = makeHarness(policy: .snapMidStroke)
        let points = recognizableLinePoints()

        harness.controller.strokeBegan()
        harness.controller.strokeContinued(
            points: timedPoints(points, zoomScale: harness.canvasView.zoomScale)
        )
        harness.controller.dwellFired()
        await drainMainQueue()

        let snappedElement = try XCTUnwrap(shapeElements(in: harness.store).first)
        XCTAssertFalse(
            harness.canvasView.drawingGestureRecognizer.isEnabled,
            "an open line adjustment holds PencilKit off"
        )

        // No strokeEnded: the gesture was reset out from under the controller.
        harness.controller.strokeBegan()

        XCTAssertTrue(harness.canvasView.drawingGestureRecognizer.isEnabled)
        XCTAssertEqual(
            harness.undoManager.undoActionName,
            "Draw Shape",
            "the abandoned adjustment still owes its undo step"
        )

        harness.controller.strokeContinued(
            points: [
                TimedPoint(
                    location: CGPoint(x: 900, y: 900),
                    timestamp: 5
                ),
            ]
        )

        XCTAssertEqual(
            shapeElements(in: harness.store),
            [snappedElement],
            "the stale pivot must not drag the previous element along"
        )
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

    /// UITouch and UIEvent are only ever vended by UIKit, so driving the recognizer
    /// directly means standing in for them: everything the recognizer reads is
    /// overridden here, and nothing else is touched.
    private final class StubTouch: UITouch {
        override var type: UITouch.TouchType { .direct }
        override var timestamp: TimeInterval { 0 }
        override func location(in view: UIView?) -> CGPoint { .zero }
    }

    private final class StubEvent: UIEvent {
        override func coalescedTouches(for touch: UITouch) -> [UITouch]? { [touch] }
    }

    /// The controller only holds its canvas and store weakly, so the test has to keep them alive.
    private struct SelectionHarness {
        let canvasView: PKCanvasView
        let coordinator: PencilCanvasView.Coordinator
        let store: CanvasElementsStore
        let undoManager: UndoManager
        let controller: CanvasSelectionController
    }
}
