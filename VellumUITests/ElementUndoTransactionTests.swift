import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class ElementUndoTransactionTests: XCTestCase {
    func testAddUndoAndRedoNotifyWithExpectedElements() {
        let (store, undoManager) = makeStore()
        let element = makeElement(text: "Undo me")
        var changes: [[CanvasElement]] = []
        store.onElementsChanged = { changes.append($0) }

        store.addElement(element)

        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        XCTAssertTrue(store.elements.isEmpty)
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()
        XCTAssertEqual(store.elements, [element])
        XCTAssertEqual(changes, [[element], [], [element]])
    }

    func testNoOpTransactionDoesNotRegisterUndo() {
        let (store, undoManager) = makeStore()

        store.performTransaction("No-op") {}

        XCTAssertFalse(undoManager.canUndo)
    }

    func testNestedTransactionsRegisterOneUndoForAllChanges() {
        let (store, undoManager) = makeStore()
        let firstElement = makeElement(text: "First")
        let secondElement = makeElement(text: "Second")

        store.performTransaction("Outer") {
            store.addElement(firstElement)
            store.addElement(secondElement)
        }

        XCTAssertEqual(store.elements, [firstElement, secondElement])
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertTrue(store.elements.isEmpty)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(undoManager.canRedo)
    }

    func testAddElementUsesKindSpecificUndoActionNames() {
        let (textStore, textUndoManager) = makeStore()
        textStore.addElement(makeElement(text: "Text"))
        XCTAssertEqual(textUndoManager.undoActionName, "Add Text Box")

        let (imageStore, imageUndoManager) = makeStore()
        imageStore.addElement(makeImageElement())
        XCTAssertEqual(imageUndoManager.undoActionName, "Add Image")
    }

    func testMutationWithoutUndoManagerStillAppliesAndNotifies() {
        let store = CanvasElementsStore()
        let element = makeElement(text: "No manager")
        var changes: [[CanvasElement]] = []
        store.onElementsChanged = { changes.append($0) }

        store.addElement(element)

        XCTAssertEqual(store.elements, [element])
        XCTAssertEqual(changes, [[element]])
    }

    func testLiveEditingSessionRegistersOneUndoStepAndSkipsNoOp() {
        let (store, undoManager) = makeStore()
        let initialElement = makeElement(text: "Before")
        store.addElement(initialElement)
        undoManager.removeAllActions()
        let baseline = store.elements

        for typedText in ["F", "Fi", "Final"] {
            var updated = initialElement
            updated.content = .text(
                TextBoxContent(
                    text: typedText,
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            )
            store.updateElementLive(updated)
        }
        let finalElements = store.elements

        XCTAssertFalse(undoManager.canUndo)
        store.registerEditingSessionUndo(from: baseline, label: "Edit Text")

        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Edit Text")

        store.registerEditingSessionUndo(from: store.elements, label: "No-op")
        XCTAssertEqual(undoManager.undoActionName, "Edit Text")

        undoManager.undo()

        XCTAssertEqual(store.elements, baseline)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(undoManager.canRedo)
        XCTAssertEqual(undoManager.redoActionName, "Edit Text")

        undoManager.redo()

        XCTAssertEqual(store.elements, finalElements)
        XCTAssertEqual(undoManager.undoActionName, "Edit Text")
    }

    func testLiveEditingSessionDeletionRestoresOriginalTextOnUndo() {
        let (store, undoManager) = makeStore()
        let initialElement = makeElement(text: "hello")
        store.addElement(initialElement)
        undoManager.removeAllActions()
        let baseline = store.elements

        var emptiedElement = initialElement
        emptiedElement.content = .text(
            TextBoxContent(
                text: "",
                fontSize: 18,
                color: CodableColor(red: 0, green: 0, blue: 0)
            )
        )
        store.updateElementLive(emptiedElement)
        store.removeElementLive(id: initialElement.id)
        store.registerEditingSessionUndo(from: baseline, label: "Remove Text Box")

        XCTAssertTrue(store.elements.isEmpty)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Remove Text Box")

        undoManager.undo()

        XCTAssertEqual(store.elements, baseline)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()

        XCTAssertTrue(store.elements.isEmpty)
    }

    func testNewEmptyTextBoxDeletionRegistersUndoAboveAdd() {
        let (store, undoManager) = makeStore()
        // Model production, where the Add and the later blur/deletion happen on separate
        // run-loop turns and are naturally separate undo groups: disable per-event grouping
        // and group each step explicitly (groupsByEvent would otherwise coalesce these two
        // same-turn registrations into a single undo group in this synchronous test).
        undoManager.groupsByEvent = false
        let emptyBox = makeElement(text: "")

        undoManager.beginUndoGrouping()
        store.addElement(emptyBox)
        undoManager.endUndoGrouping()
        let baseline = store.elements

        undoManager.beginUndoGrouping()
        store.removeElementLive(id: emptyBox.id)
        store.registerEditingSessionUndo(from: baseline, label: "Remove Text Box")
        undoManager.endUndoGrouping()

        XCTAssertTrue(store.elements.isEmpty)

        undoManager.undo()
        XCTAssertEqual(store.elements, baseline)

        undoManager.undo()
        XCTAssertTrue(store.elements.isEmpty)

        undoManager.redo()
        XCTAssertEqual(store.elements, baseline)

        undoManager.redo()
        XCTAssertTrue(store.elements.isEmpty)
    }

    func testRemoveElementLiveWithUnknownIDIsNoOp() {
        let (store, undoManager) = makeStore()
        let element = makeElement(text: "Existing")
        store.addElement(element)
        undoManager.removeAllActions()
        let expectedElements = store.elements
        var changes: [[CanvasElement]] = []
        store.onElementsChanged = { changes.append($0) }

        store.removeElementLive(id: UUID())

        XCTAssertEqual(store.elements, expectedElements)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertFalse(undoManager.canUndo)
    }

    func testDrawShapeTransactionUndoesAndRedoesAtomically() {
        let originalStroke = makeStroke()
        let canvasView = PKCanvasView()
        canvasView.drawing = PKDrawing(strokes: [originalStroke])
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
        let shapeElement = CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0.5),
                            CanvasPoint(x: 1, y: 0.5),
                        ],
                        isClosed: false
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 4
                )
            ),
            frame: CanvasRect(x: 10, y: 12, width: 100, height: 8)
        )

        store.performTransaction("Draw Shape") {
            store.mutateDrawing { $0.strokes.removeAll() }
            store.addElement(shapeElement)
        }

        XCTAssertTrue(canvasView.drawing.strokes.isEmpty)
        XCTAssertEqual(store.elements, [shapeElement])
        XCTAssertEqual(undoManager.undoActionName, "Draw Shape")

        undoManager.undo()

        XCTAssertEqual(canvasView.drawing.strokes.count, 1)
        XCTAssertEqual(
            canvasView.drawing.strokes[0].renderBounds,
            originalStroke.renderBounds
        )
        XCTAssertTrue(store.elements.isEmpty)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()

        XCTAssertTrue(canvasView.drawing.strokes.isEmpty)
        XCTAssertEqual(store.elements, [shapeElement])
        XCTAssertEqual(undoManager.undoActionName, "Draw Shape")
    }

    func testVertexDragRegistersOneUndoStepAndReplaysFinalShape() throws {
        let (store, undoManager) = makeStore()
        let shapeElement = makeShapeElement(
            geometry: .polyline(
                vertices: [
                    CanvasPoint(x: 0, y: 0),
                    CanvasPoint(x: 0.5, y: 1),
                    CanvasPoint(x: 1, y: 0),
                ],
                isClosed: false
            )
        )
        store.hydrate([shapeElement])
        let harness = makeSelectionController(for: store)
        select(shapeElement, with: harness.controller)

        XCTAssertEqual(harness.controller.vertexEditableElement(), shapeElement)

        harness.controller.setVertexPosition(CGPoint(x: 300, y: 300))
        XCTAssertEqual(store.elements, [shapeElement])
        XCTAssertFalse(undoManager.canUndo)

        harness.controller.beginVertexDrag(
            elementID: shapeElement.id,
            vertexIndex: 0
        )
        harness.controller.setVertexPosition(CGPoint(x: 12, y: 18))
        harness.controller.setVertexPosition(CGPoint(x: 6, y: 14))
        harness.controller.endVertexDrag()

        let finalElements = store.elements
        XCTAssertNotEqual(finalElements, [shapeElement])
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Edit Shape")

        harness.controller.setVertexPosition(CGPoint(x: 400, y: 400))
        XCTAssertEqual(store.elements, finalElements)
        XCTAssertEqual(undoManager.undoActionName, "Edit Shape")

        let finalElement = try XCTUnwrap(finalElements.first)
        let finalBounds = try XCTUnwrap(harness.controller.selectionBounds)
        XCTAssertEqual(finalBounds.minX, CGFloat(finalElement.frame.x), accuracy: 0.001)
        XCTAssertEqual(finalBounds.minY, CGFloat(finalElement.frame.y), accuracy: 0.001)
        XCTAssertEqual(finalBounds.width, CGFloat(finalElement.frame.width), accuracy: 0.001)
        XCTAssertEqual(finalBounds.height, CGFloat(finalElement.frame.height), accuracy: 0.001)

        undoManager.undo()

        XCTAssertEqual(store.elements, [shapeElement])
        XCTAssertEqual(store.elements.first?.content, shapeElement.content)
        XCTAssertEqual(store.elements.first?.frame, shapeElement.frame)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(undoManager.canRedo)
        XCTAssertEqual(undoManager.redoActionName, "Edit Shape")

        undoManager.redo()

        XCTAssertEqual(store.elements, finalElements)
        XCTAssertEqual(undoManager.undoActionName, "Edit Shape")
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    // Two fingers resting on two vertex handles hand the drag back and forth, and every handover
    // re-enters `beginVertexDrag`. The baseline has to survive that: taking a fresh one from
    // elements this same gesture already moved leaves the first finger's work outside "Edit Shape",
    // so undo lands on a mid-gesture shape and the rest of the edit can never be taken back.
    func testAHandoverBetweenVertexHandlesUndoesToTheShapeBeforeTheDrag() {
        let (store, undoManager) = makeStore()
        let shapeElement = makeShapeElement(
            geometry: .polyline(
                vertices: [
                    CanvasPoint(x: 0, y: 0),
                    CanvasPoint(x: 0.5, y: 1),
                    CanvasPoint(x: 1, y: 0),
                ],
                isClosed: false
            )
        )
        store.hydrate([shapeElement])
        let harness = makeSelectionController(for: store)
        select(shapeElement, with: harness.controller)

        harness.controller.beginVertexDrag(elementID: shapeElement.id, vertexIndex: 0)
        harness.controller.setVertexPosition(CGPoint(x: 60, y: 60))
        let midGesture = store.elements
        XCTAssertNotEqual(midGesture, [shapeElement])

        // The first handle never reported an end, so the second one takes the drag over in flight.
        harness.controller.beginVertexDrag(elementID: shapeElement.id, vertexIndex: 2)
        harness.controller.setVertexPosition(CGPoint(x: 300, y: 300))
        harness.controller.endVertexDrag()

        let finalElements = store.elements
        XCTAssertNotEqual(finalElements, midGesture)
        XCTAssertEqual(undoManager.undoActionName, "Edit Shape")

        undoManager.undo()

        XCTAssertNotEqual(store.elements, midGesture, "undo stopped at a mid-gesture shape")
        XCTAssertEqual(store.elements, [shapeElement])
        XCTAssertFalse(undoManager.canUndo, "the whole two-finger gesture must be one undo step")

        undoManager.redo()

        XCTAssertEqual(store.elements, finalElements)
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    func testTapSelectionSurvivesTheToolChangeItTriggers() {
        let (store, _) = makeStore()
        let shapeElement = makeShapeElement(geometry: .ellipse)
        store.hydrate([shapeElement])
        let harness = makeSelectionController(for: store)

        // Tapping a shape selects it and switches to the Select tool; the tool change must not
        // clear the selection the tap just made.
        harness.controller.selectElement(id: shapeElement.id, survivesNextToolChange: true)
        harness.controller.toolChanged()

        XCTAssertNotNil(harness.controller.selection)

        // The exemption is spent, so the next tool change clears as usual.
        harness.controller.toolChanged()
        XCTAssertNil(harness.controller.selection)
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    func testASelectionMadeAnyOtherWayIsClearedByAToolChange() {
        let (store, _) = makeStore()
        let shapeElement = makeShapeElement(geometry: .ellipse)
        store.hydrate([shapeElement])
        let harness = makeSelectionController(for: store)

        harness.controller.selectElement(id: shapeElement.id)
        harness.controller.toolChanged()

        XCTAssertNil(harness.controller.selection)
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    func testEllipseSelectionOffersARadiusHandlePerAxisEnd() throws {
        let (store, _) = makeStore()
        let ellipseElement = makeShapeElement(geometry: .ellipse)
        store.hydrate([ellipseElement])
        let harness = makeSelectionController(for: store)

        select(ellipseElement, with: harness.controller)

        XCTAssertNotNil(harness.controller.selection)
        let editable = try XCTUnwrap(harness.controller.vertexEditableElement())
        let handles = harness.controller.vertexEditHandles(for: editable)
        XCTAssertEqual(handles.count, 4)

        // Each handle sits on the curve, not on the corner of a box around it.
        let frame = ellipseElement.frame
        let center = CGPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
        XCTAssertEqual(handles[0], CGPoint(x: center.x, y: frame.y))
        XCTAssertEqual(handles[2], CGPoint(x: center.x, y: frame.y + frame.height))
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    func testDraggingAnEllipseRadiusHandleResizesOneAxisInOneUndoStep() throws {
        let (store, undoManager) = makeStore()
        let ellipseElement = makeShapeElement(geometry: .ellipse)
        store.hydrate([ellipseElement])
        let harness = makeSelectionController(for: store)
        select(ellipseElement, with: harness.controller)

        harness.controller.beginVertexDrag(elementID: ellipseElement.id, vertexIndex: 1)
        harness.controller.setVertexPosition(
            CGPoint(x: ellipseElement.frame.x + ellipseElement.frame.width + 40, y: 70)
        )
        harness.controller.endVertexDrag()

        let resized = try XCTUnwrap(store.elements.first)
        XCTAssertEqual(resized.frame.width, ellipseElement.frame.width + 40, accuracy: 0.001)
        XCTAssertEqual(resized.frame.height, ellipseElement.frame.height, accuracy: 0.001)
        XCTAssertEqual(resized.frame.x, ellipseElement.frame.x, accuracy: 0.001)
        XCTAssertEqual(undoManager.undoActionName, "Edit Shape")

        undoManager.undo()
        XCTAssertEqual(store.elements, [ellipseElement])
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    func testAnUnconvertibleVertexSampleIsSkippedWithoutLosingTheUndoStep() {
        let (store, undoManager) = makeStore()
        let shapeElement = makeShapeElement(
            geometry: .polyline(
                vertices: [
                    CanvasPoint(x: 0, y: 0),
                    CanvasPoint(x: 0.5, y: 1),
                    CanvasPoint(x: 1, y: 0),
                ],
                isClosed: false
            )
        )
        store.hydrate([shapeElement])
        let harness = makeSelectionController(for: store)
        select(shapeElement, with: harness.controller)

        harness.controller.beginVertexDrag(elementID: shapeElement.id, vertexIndex: 0)
        harness.controller.setVertexPosition(CGPoint(x: 12, y: 18))
        let afterFirstSample = store.elements

        // A non-finite sample is one the vertex editor refuses to convert.
        harness.controller.setVertexPosition(CGPoint(x: CGFloat.nan, y: 18))

        XCTAssertTrue(harness.controller.isVertexDragging)
        XCTAssertEqual(store.elements, afterFirstSample)

        harness.controller.setVertexPosition(CGPoint(x: 6, y: 14))
        harness.controller.endVertexDrag()

        let finalElements = store.elements
        XCTAssertNotEqual(finalElements, [shapeElement])
        XCTAssertEqual(undoManager.undoActionName, "Edit Shape")

        undoManager.undo()

        XCTAssertEqual(store.elements, [shapeElement])
        XCTAssertFalse(undoManager.canUndo, "the whole drag must be exactly one undo step")

        undoManager.redo()

        XCTAssertEqual(store.elements, finalElements)
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    func testAnUnconvertibleRadiusSampleIsSkippedWithoutLosingTheUndoStep() throws {
        let (store, undoManager) = makeStore()
        let ellipseElement = makeShapeElement(geometry: .ellipse)
        store.hydrate([ellipseElement])
        let harness = makeSelectionController(for: store)
        select(ellipseElement, with: harness.controller)

        harness.controller.beginVertexDrag(elementID: ellipseElement.id, vertexIndex: 1)
        harness.controller.setVertexPosition(
            CGPoint(x: ellipseElement.frame.x + ellipseElement.frame.width + 40, y: 70)
        )
        let afterFirstSample = store.elements

        harness.controller.setVertexPosition(CGPoint(x: CGFloat.infinity, y: 70))

        XCTAssertTrue(harness.controller.isVertexDragging)
        XCTAssertEqual(store.elements, afterFirstSample)

        harness.controller.endVertexDrag()

        let resized = try XCTUnwrap(store.elements.first)
        XCTAssertEqual(resized.frame.width, ellipseElement.frame.width + 40, accuracy: 0.001)
        XCTAssertEqual(undoManager.undoActionName, "Edit Shape")

        undoManager.undo()

        XCTAssertEqual(store.elements, [ellipseElement])
        XCTAssertFalse(undoManager.canUndo, "the whole drag must be exactly one undo step")
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    func testAVanishedElementAbandonsTheVertexDragInsteadOfMisattributingIt() {
        let (store, undoManager) = makeStore()
        let shapeElement = makeShapeElement(
            geometry: .polyline(
                vertices: [
                    CanvasPoint(x: 0, y: 0),
                    CanvasPoint(x: 1, y: 1),
                ],
                isClosed: false
            )
        )
        store.hydrate([shapeElement])
        let harness = makeSelectionController(for: store)
        select(shapeElement, with: harness.controller)

        harness.controller.beginVertexDrag(elementID: shapeElement.id, vertexIndex: 0)
        harness.controller.setVertexPosition(CGPoint(x: 12, y: 18))

        // Something outside this gesture rewrote the store. The drag baseline predates that, so
        // the session is dropped rather than folded into an "Edit Shape" step that would undo it.
        store.removeElementLive(id: shapeElement.id)
        harness.controller.setVertexPosition(CGPoint(x: 6, y: 14))

        XCTAssertFalse(harness.controller.isVertexDragging)

        harness.controller.endVertexDrag()

        XCTAssertFalse(undoManager.canUndo)
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    // Two fingers can reach the two drag modes at once: one holds a resize handle, which stays
    // grabbable for the whole handle drag, while the other pans — and with a selection up, any pan
    // means "move". Both modes hide the selected strokes and stash the drawing they came from, and
    // that stash is the only copy left. A second hide would stash the already trimmed drawing and
    // cut the same indices out of it again, so the strokes would be gone from the canvas, missing
    // from the undo baseline of the commit that follows, and then persisted that way.
    func testAPanArrivingDuringAHandleDragCannotSwallowTheHiddenStrokes() {
        let (store, undoManager) = makeStore()
        let harness = makeSelectionController(for: store)
        // Diagonal, so the selection box clears the 12pt floor `endHandleDrag` clamps its scale
        // to: an untouched handle drag then really commits nothing.
        let stroke = makeStroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 120))
        harness.canvasView.drawing = PKDrawing(strokes: [stroke])
        selectEverything(with: harness.controller)
        XCTAssertEqual(harness.controller.selection?.strokeIndices.count, 1)

        harness.controller.beginHandleDrag()
        XCTAssertTrue(harness.canvasView.drawing.strokes.isEmpty, "the handle drag hides the ink")

        // The second finger's pan. The handle drag owns the hidden stroke, so the move is refused
        // and the end it reports has nothing to restore or commit.
        XCTAssertFalse(harness.controller.beginMoveDrag())
        harness.controller.endMoveDrag()
        XCTAssertTrue(harness.canvasView.drawing.strokes.isEmpty)
        XCTAssertTrue(harness.controller.isHandleDragging)

        harness.controller.endHandleDrag()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1, "the hidden stroke came back")
        XCTAssertEqual(harness.canvasView.drawing.strokes[0].renderBounds, stroke.renderBounds)
        XCTAssertFalse(undoManager.canUndo, "neither drag moved anything")
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    // The same collision from the other side: the move got there first, so a handle drag starting
    // on top of it is refused and the move stays undoable end to end.
    func testAHandleDragArrivingDuringAMoveIsRefusedAndTheMoveStillUndoes() {
        let (store, undoManager) = makeStore()
        let harness = makeSelectionController(for: store)
        harness.canvasView.drawing = PKDrawing(
            strokes: [makeStroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 120))]
        )
        selectEverything(with: harness.controller)

        XCTAssertTrue(harness.controller.beginMoveDrag())
        harness.controller.beginHandleDrag()
        XCTAssertFalse(harness.controller.isHandleDragging, "the move keeps the selection")

        // The refused handle drag still reports its own end, which must leave the move untouched.
        harness.controller.endHandleDrag()
        XCTAssertTrue(harness.canvasView.drawing.strokes.isEmpty, "the move still hides the ink")

        harness.controller.setDragTranslation(CGSize(width: 30, height: 40))
        harness.controller.endMoveDrag()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        XCTAssertEqual(harness.canvasView.drawing.strokes[0].transform.tx, 30, accuracy: 0.001)
        XCTAssertEqual(harness.canvasView.drawing.strokes[0].transform.ty, 40, accuracy: 0.001)
        XCTAssertEqual(undoManager.undoActionName, "Move Selection")

        undoManager.undo()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1, "undo brought the ink back")
        XCTAssertEqual(harness.canvasView.drawing.strokes[0].transform.tx, 0, accuracy: 0.001)
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    // How a second finger legitimately takes a move over: `handlePinch` ends the move first, so by
    // the time the handle drag starts the strokes are back on the canvas and it hides them itself.
    func testEndingAMoveBeforeAHandleDragHidesTheStrokeExactlyOnce() {
        let (store, undoManager) = makeStore()
        let harness = makeSelectionController(for: store)
        harness.canvasView.drawing = PKDrawing(
            strokes: [makeStroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 120))]
        )
        selectEverything(with: harness.controller)
        // In production the move and the transform commit on separate run-loop turns, so they are
        // separate undo groups; group them explicitly here or groupsByEvent would coalesce them.
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        XCTAssertTrue(harness.controller.beginMoveDrag())
        harness.controller.setDragTranslation(CGSize(width: 30, height: 40))
        harness.controller.endMoveDrag()
        undoManager.endUndoGrouping()
        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)

        undoManager.beginUndoGrouping()
        harness.controller.beginHandleDrag()
        XCTAssertTrue(harness.controller.isHandleDragging)
        XCTAssertTrue(harness.canvasView.drawing.strokes.isEmpty)

        harness.controller.setHandleTransform(scale: CGSize(width: 2, height: 2), rotation: 0)
        harness.controller.endHandleDrag()
        undoManager.endUndoGrouping()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        XCTAssertEqual(harness.canvasView.drawing.strokes[0].transform.a, 2, accuracy: 0.001)

        undoManager.undo()

        XCTAssertEqual(harness.canvasView.drawing.strokes[0].transform.a, 1, accuracy: 0.001)
        XCTAssertEqual(harness.canvasView.drawing.strokes[0].transform.tx, 30, accuracy: 0.001)

        undoManager.undo()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        XCTAssertEqual(harness.canvasView.drawing.strokes[0].transform.tx, 0, accuracy: 0.001)
        withExtendedLifetime((harness.canvasView, harness.coordinator)) {}
    }

    private func makeStore() -> (CanvasElementsStore, UndoManager) {
        let store = CanvasElementsStore()
        let undoManager = UndoManager()
        store.undoManagerOverride = undoManager
        return (store, undoManager)
    }

    private func makeSelectionController(
        for store: CanvasElementsStore
    ) -> (
        controller: CanvasSelectionController,
        canvasView: PKCanvasView,
        coordinator: PencilCanvasView.Coordinator
    ) {
        let canvasView = PKCanvasView()
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { _ in },
            onViewportChanged: nil
        )
        canvasView.delegate = coordinator

        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView
        store.canvasReference = canvasReference

        let controller = CanvasSelectionController()
        controller.canvasReference = canvasReference
        controller.elementsStore = store
        return (controller, canvasView, coordinator)
    }

    private func select(
        _ element: CanvasElement,
        with controller: CanvasSelectionController
    ) {
        let margin = 10.0
        controller.beginCapture(
            at: CGPoint(
                x: element.frame.x - margin,
                y: element.frame.y - margin
            ),
            mode: .boxed
        )
        controller.extendCapture(
            to: CGPoint(
                x: element.frame.x + element.frame.width + margin,
                y: element.frame.y + element.frame.height + margin
            )
        )
        controller.endCapture()
    }

    /// A boxed capture wide enough to take in everything the harness put on the canvas.
    private func selectEverything(with controller: CanvasSelectionController) {
        controller.beginCapture(at: CGPoint(x: -100, y: -100), mode: .boxed)
        controller.extendCapture(to: CGPoint(x: 600, y: 600))
        controller.endCapture()
    }

    private func makeElement(text: String) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: text,
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: CanvasRect(x: 10, y: 20, width: 100, height: 40)
        )
    }

    private func makeImageElement() -> CanvasElement {
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: "images/undo.png",
                    originalPixelSize: CanvasSize(width: 200, height: 100)
                )
            ),
            frame: CanvasRect(x: 20, y: 30, width: 200, height: 100)
        )
    }

    private func makeShapeElement(
        geometry: ShapeContent.Geometry
    ) -> CanvasElement {
        CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: geometry,
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 4
                )
            ),
            frame: CanvasRect(x: 20, y: 30, width: 100, height: 80)
        )
    }

    private func makeStroke(
        from start: CGPoint = CGPoint(x: 10, y: 12),
        to end: CGPoint = CGPoint(x: 110, y: 12)
    ) -> PKStroke {
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
}
