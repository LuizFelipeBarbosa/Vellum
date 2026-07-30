import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class SelectionOperationTests: XCTestCase {
    func testBoxedCaptureSelectsStrokeAndTextElement() throws {
        let element = makeElement(frame: CanvasRect(x: 60, y: 20, width: 30, height: 30))
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: [element]
        )

        selectMixedContent(in: harness)

        let selection = try XCTUnwrap(harness.controller.selection)
        XCTAssertEqual(selection.strokeIndices.count, 1)
        XCTAssertEqual(selection.elementIDs, Set([element.id]))
        XCTAssertNotNil(harness.controller.selectionBounds)
    }

    func testCommittedChromeRotationUsesSingleSelectedElementRotation() {
        let rotation = Double.pi / 3
        let element = makeElement(
            frame: CanvasRect(x: 60, y: 20, width: 30, height: 30),
            rotation: rotation
        )
        let harness = makeHarness(strokes: [], elements: [element])

        harness.controller.selectElement(id: element.id)

        XCTAssertEqual(
            harness.controller.committedChromeRotation,
            rotation,
            accuracy: 0.000_001
        )
    }

    func testCommittedChromeRotationIsZeroForTwoSelectedElements() {
        let first = makeElement(
            frame: CanvasRect(x: 20, y: 20, width: 30, height: 30),
            rotation: Double.pi / 3
        )
        let second = makeElement(
            frame: CanvasRect(x: 60, y: 20, width: 30, height: 30),
            rotation: Double.pi / 4
        )
        let harness = makeHarness(strokes: [], elements: [first, second])

        selectMixedContent(in: harness)

        XCTAssertEqual(harness.controller.selection?.elementIDs.count, 2)
        XCTAssertEqual(harness.controller.committedChromeRotation, 0)
    }

    func testCommittedChromeRotationIsZeroForStrokeOnlySelection() {
        let harness = makeHarness(
            strokes: [
                makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
            ],
            elements: []
        )

        selectMixedContent(in: harness)

        XCTAssertEqual(harness.controller.selection?.strokeIndices, IndexSet(integer: 0))
        XCTAssertEqual(harness.controller.committedChromeRotation, 0)
    }

    func testCommittedChromeRotationIsZeroForElementAndStrokeSelection() {
        let element = makeElement(
            frame: CanvasRect(x: 60, y: 20, width: 30, height: 30),
            rotation: Double.pi / 3
        )
        let harness = makeHarness(
            strokes: [
                makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
            ],
            elements: [element]
        )

        selectMixedContent(in: harness)

        XCTAssertEqual(harness.controller.selection?.elementIDs, Set([element.id]))
        XCTAssertEqual(harness.controller.selection?.strokeIndices, IndexSet(integer: 0))
        XCTAssertEqual(harness.controller.committedChromeRotation, 0)
    }

    func testRotationSnappingUsesCommittedAndLiveRotationTotal() {
        let twoDegrees = 2 * Double.pi / 180
        let committed = Double.pi / 2 - twoDegrees

        let delta = SelectionHandleGeometry.snappedRotation(
            committed: committed,
            delta: twoDegrees
        )

        XCTAssertEqual(committed + delta, Double.pi / 2, accuracy: 0.000_001)
    }

    func testRotationSnappingPassesThroughWhenTotalIsOutsideThreshold() {
        let committed = 0.3
        let requestedDelta = 0.01

        let delta = SelectionHandleGeometry.snappedRotation(
            committed: committed,
            delta: requestedDelta
        )

        XCTAssertEqual(delta, requestedDelta, accuracy: 0.000_001)
    }

    func testRotateCommitBecomesCommittedChromeRotationAndClearsLiveDelta() throws {
        let initialRotation = 0.2
        let rotationDelta = 0.37
        let element = makeElement(
            frame: CanvasRect(x: 60, y: 20, width: 30, height: 30),
            rotation: initialRotation
        )
        let harness = makeHarness(strokes: [], elements: [element])
        harness.controller.selectElement(id: element.id)

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 1, height: 1),
            rotation: rotationDelta
        )
        harness.controller.endHandleDrag()

        let committedElement = try XCTUnwrap(
            harness.store.elements.first(where: { $0.id == element.id })
        )
        XCTAssertEqual(
            committedElement.rotation,
            initialRotation + rotationDelta,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            harness.controller.committedChromeRotation,
            committedElement.rotation,
            accuracy: 0.000_001
        )
        XCTAssertEqual(harness.controller.handleRotation, 0)
    }

    func testSelectionSupportsStylingTruthTable() {
        let frame = CanvasRect(x: 60, y: 20, width: 30, height: 30)
        let stroke = makeStroke(
            locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)]
        )

        let strokesOnly = makeHarness(strokes: [stroke], elements: [])
        selectMixedContent(in: strokesOnly)
        XCTAssertTrue(strokesOnly.controller.selectionSupportsStyling)

        let shape = makeShapeElement(frame: frame)
        let shapeOnly = makeHarness(strokes: [], elements: [shape])
        shapeOnly.controller.selectElement(id: shape.id)
        XCTAssertTrue(shapeOnly.controller.selectionSupportsStyling)

        let text = makeElement(frame: frame)
        let textOnly = makeHarness(strokes: [], elements: [text])
        textOnly.controller.selectElement(id: text.id)
        XCTAssertTrue(textOnly.controller.selectionSupportsStyling)

        let image = makeImageElement(frame: frame)
        let imageOnly = makeHarness(strokes: [], elements: [image])
        imageOnly.controller.selectElement(id: image.id)
        XCTAssertFalse(imageOnly.controller.selectionSupportsStyling)

        let imageAndStroke = makeHarness(strokes: [stroke], elements: [image])
        selectMixedContent(in: imageAndStroke)
        XCTAssertTrue(imageAndStroke.controller.selectionSupportsStyling)

        let noSelection = makeHarness(strokes: [], elements: [])
        XCTAssertFalse(noSelection.controller.selectionSupportsStyling)
    }

    func testBeginMoveDragHidesSelectedStrokeAndCreatesSnapshot() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        selectMixedContent(in: harness)
        let originalStrokeCount = harness.canvasView.drawing.strokes.count

        harness.controller.beginMoveDrag()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount - 1)
        XCTAssertNotNil(harness.controller.strokesSnapshot)
    }

    func testBeginMoveDragSetsTransientOverrideFlagAndEndMoveDragClearsIt() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        let drawingChangeCounter = DrawingChangeCounter()
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { _ in drawingChangeCounter.value += 1 },
            onViewportChanged: nil
        )
        harness.canvasView.delegate = coordinator
        selectMixedContent(in: harness)

        harness.controller.beginMoveDrag()

        XCTAssertTrue(coordinator.hasTransientDrawingOverride)
        // Direct drawing assignments in this synthetic harness do not exercise PencilKit's
        // touch-driven delegate callback; this verifies the silent hide/restore writes themselves.
        XCTAssertEqual(drawingChangeCounter.value, 0)

        harness.controller.endMoveDrag()

        XCTAssertFalse(coordinator.hasTransientDrawingOverride)
        XCTAssertEqual(drawingChangeCounter.value, 0)
    }

    func testBeginHandleDragSetsTransientOverrideFlagAndEndHandleDragClearsIt() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { _ in },
            onViewportChanged: nil
        )
        harness.canvasView.delegate = coordinator
        selectMixedContent(in: harness)

        harness.controller.beginHandleDrag()

        XCTAssertTrue(coordinator.hasTransientDrawingOverride)

        harness.controller.endHandleDrag()

        XCTAssertFalse(coordinator.hasTransientDrawingOverride)
    }

    func testExternalDrawingChangeDuringDragClearsTransientOverrideFlag() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { _ in },
            onViewportChanged: nil
        )
        harness.canvasView.delegate = coordinator
        selectMixedContent(in: harness)
        harness.controller.beginMoveDrag()
        XCTAssertTrue(coordinator.hasTransientDrawingOverride)

        harness.controller.externalDrawingDidChange()

        XCTAssertFalse(coordinator.hasTransientDrawingOverride)
    }

    func testClearSelectionDuringDragClearsTransientOverrideFlag() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        let coordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { _ in },
            onViewportChanged: nil
        )
        harness.canvasView.delegate = coordinator
        selectMixedContent(in: harness)
        harness.controller.beginMoveDrag()
        XCTAssertTrue(coordinator.hasTransientDrawingOverride)

        harness.controller.clearSelection()

        XCTAssertFalse(coordinator.hasTransientDrawingOverride)
    }

    func testMoveCommitsStrokeAndElementAsOneUndoableTransaction() throws {
        let element = makeElement(frame: CanvasRect(x: 60, y: 20, width: 30, height: 30))
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: [element]
        )
        selectMixedContent(in: harness)

        harness.controller.beginMoveDrag()
        harness.controller.setDragTranslation(CGSize(width: 30, height: 40))
        harness.controller.endMoveDrag()

        assertStrokeTransform(harness.canvasView.drawing.strokes[0], x: 30, y: 40)
        let movedElement = try XCTUnwrap(harness.store.elements.first)
        XCTAssertEqual(movedElement.frame.x, 90, accuracy: 0.001)
        XCTAssertEqual(movedElement.frame.y, 60, accuracy: 0.001)
        XCTAssertTrue(harness.undoManager.canUndo)

        harness.undoManager.undo()

        assertStrokeTransform(harness.canvasView.drawing.strokes[0], x: 0, y: 0)
        let restoredElement = try XCTUnwrap(harness.store.elements.first)
        XCTAssertEqual(restoredElement.frame.x, 60, accuracy: 0.001)
        XCTAssertEqual(restoredElement.frame.y, 20, accuracy: 0.001)
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "A mixed stroke-and-element move must register exactly one undo entry"
        )
        XCTAssertTrue(harness.undoManager.canRedo)

        harness.undoManager.redo()

        assertStrokeTransform(harness.canvasView.drawing.strokes[0], x: 30, y: 40)
        let redoneElement = try XCTUnwrap(harness.store.elements.first)
        XCTAssertEqual(redoneElement.frame.x, 90, accuracy: 0.001)
        XCTAssertEqual(redoneElement.frame.y, 60, accuracy: 0.001)
        XCTAssertFalse(harness.undoManager.canRedo)
    }

    func testReorderSelectionUsesOneUndoAndRestoresOriginalPlacements() {
        let frame = CanvasRect(x: 60, y: 20, width: 30, height: 30)
        let selected = makeElement(frame: frame)
        let front = makeElement(frame: frame)
        let originalElements = [selected, front].zOrderMaterialized()
        let harness = makeHarness(strokes: [], elements: originalElements)
        harness.controller.selectElement(id: selected.id)

        XCTAssertTrue(harness.controller.canReorderSelection)
        harness.controller.reorderSelection(.toFront)

        XCTAssertEqual(harness.store.elements.map(\.id), [front.id, selected.id])
        XCTAssertTrue(harness.store.elements.allSatisfy {
            $0.layerPlacement == .aboveInk
        })
        XCTAssertEqual(harness.undoManager.undoActionName, ReorderDirection.toFront.undoLabel)

        harness.undoManager.undo()

        XCTAssertEqual(harness.store.elements, originalElements)
        XCTAssertTrue(harness.store.elements.allSatisfy {
            $0.layerPlacement == .aboveInk
        })
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "Reorder must register exactly one undo entry"
        )
        XCTAssertTrue(harness.undoManager.canRedo)
    }

    func testMaterializedLegacyHydrateKeepsScreenAndEffectiveZOrderAlignedAfterAppend() {
        let legacyText = makeElement(
            frame: CanvasRect(x: 20, y: 20, width: 80, height: 40)
        )
        let legacyShape = makeShapeElement(
            frame: CanvasRect(x: 40, y: 40, width: 80, height: 60)
        )
        let legacyImage = makeImageElement(
            frame: CanvasRect(x: 60, y: 60, width: 80, height: 60)
        )
        let legacyElements = [legacyText, legacyShape, legacyImage]
        XCTAssertTrue(legacyElements.allSatisfy { $0.layerPlacement == nil })

        let store = CanvasElementsStore()
        store.hydrate(legacyElements)
        XCTAssertTrue(store.elements.allSatisfy { $0.layerPlacement != nil })

        let appendedImage = makeImageElement(
            frame: CanvasRect(x: 80, y: 80, width: 80, height: 60)
        )
        store.addElement(appendedImage)

        XCTAssertEqual(store.elements.last?.layerPlacement, .belowInk)
        let screenOrder =
            store.elements.filter { $0.effectivePlacement == .belowInk }
            + store.elements.filter { $0.effectivePlacement == .aboveInk }
        XCTAssertEqual(screenOrder, store.elements.sortedByEffectiveZ())
    }

    func testMoveDragRestoresStrokeAndPreservesSingleUndoEntry() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        selectMixedContent(in: harness)
        let originalStrokeCount = harness.canvasView.drawing.strokes.count

        harness.controller.beginMoveDrag()
        harness.controller.setDragTranslation(CGSize(width: 30, height: 40))
        harness.controller.endMoveDrag()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount)
        assertStrokeTransform(harness.canvasView.drawing.strokes[0], x: 30, y: 40)
        XCTAssertTrue(harness.undoManager.canUndo)

        harness.undoManager.undo()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount)
        assertStrokeTransform(harness.canvasView.drawing.strokes[0], x: 0, y: 0)
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "A stroke move must register exactly one undo entry"
        )
    }

    func testZeroTranslationMoveDragRestoresStrokeWithoutUndoEntry() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        selectMixedContent(in: harness)
        let originalStrokeCount = harness.canvasView.drawing.strokes.count

        harness.controller.beginMoveDrag()
        harness.controller.endMoveDrag()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount)
        assertStrokeTransform(harness.canvasView.drawing.strokes[0], x: 0, y: 0)
        XCTAssertFalse(harness.undoManager.canUndo)
    }

    func testHandleDragHidesThenRestoresAndTransformsSelectedStroke() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        selectMixedContent(in: harness)
        let originalStrokeCount = harness.canvasView.drawing.strokes.count

        harness.controller.beginHandleDrag()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount - 1)
        XCTAssertNotNil(harness.controller.strokesSnapshot)

        harness.controller.setHandleTransform(
            scale: CGSize(width: 2, height: 2),
            rotation: 0
        )
        harness.controller.endHandleDrag()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount)
        let transform = harness.canvasView.drawing.strokes[0].transform
        XCTAssertEqual(transform.a, 2, accuracy: 0.001)
        XCTAssertEqual(transform.d, 2, accuracy: 0.001)
    }

    func testClearSelectionRestoresStrokeHiddenForMoveDrag() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        selectMixedContent(in: harness)
        let originalStrokeCount = harness.canvasView.drawing.strokes.count
        harness.controller.beginMoveDrag()
        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount - 1)

        harness.controller.clearSelection()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount)
        XCTAssertNil(harness.controller.selection)
    }

    func testExternalDrawingChangeDiscardsHiddenStrokeStateWithoutRestoringIt() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        selectMixedContent(in: harness)
        let originalStrokeCount = harness.canvasView.drawing.strokes.count
        harness.controller.beginMoveDrag()
        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount - 1)

        harness.controller.externalDrawingDidChange()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, originalStrokeCount - 1)
        XCTAssertNil(harness.controller.selection)
    }

    func testUndoOfCommittedMoveClearsSelectionViaSnapshotHook() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        harness.store.onSnapshotApplied = { [weak controller = harness.controller] in
            controller?.externalDrawingDidChange()
        }
        selectMixedContent(in: harness)
        XCTAssertNotNil(harness.controller.selection)

        harness.controller.beginMoveDrag()
        harness.controller.setDragTranslation(CGSize(width: 30, height: 40))
        harness.controller.endMoveDrag()
        XCTAssertNotNil(harness.controller.selection, "Selection survives its own commit")

        harness.undoManager.undo()

        XCTAssertNil(
            harness.controller.selection,
            "Undo restores a drawing the selection's stroke indices no longer describe"
        )
    }

    func testDeleteRemovesStrokeAndElementAsOneUndoableTransaction() {
        let element = makeElement(frame: CanvasRect(x: 60, y: 20, width: 30, height: 30))
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: [element]
        )
        selectMixedContent(in: harness)

        harness.controller.deleteSelection()

        XCTAssertTrue(harness.canvasView.drawing.strokes.isEmpty)
        XCTAssertTrue(harness.store.elements.isEmpty)
        XCTAssertNil(harness.controller.selection)
        XCTAssertNil(harness.controller.selectionBounds)
        XCTAssertTrue(harness.undoManager.canUndo)

        harness.undoManager.undo()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        XCTAssertEqual(harness.store.elements, [element].zOrderMaterialized())
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "A mixed stroke-and-element delete must register exactly one undo entry"
        )
        XCTAssertTrue(harness.undoManager.canRedo)

        harness.undoManager.redo()

        XCTAssertTrue(harness.canvasView.drawing.strokes.isEmpty)
        XCTAssertTrue(harness.store.elements.isEmpty)
        XCTAssertFalse(harness.undoManager.canRedo)
    }

    func testDuplicateSelectsOffsetCopiesAndUsesOneUndoableTransaction() throws {
        let element = makeElement(frame: CanvasRect(x: 60, y: 20, width: 30, height: 30))
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: [element]
        )
        selectMixedContent(in: harness)

        harness.controller.duplicateSelection()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 2)
        XCTAssertEqual(harness.store.elements.count, 2)
        assertStrokeTransform(harness.canvasView.drawing.strokes[1], x: 20, y: 20)
        let duplicate = try XCTUnwrap(harness.store.elements.first(where: { $0.id != element.id }))
        XCTAssertNotEqual(duplicate.id, element.id)
        XCTAssertEqual(duplicate.frame.x, element.frame.x + 20, accuracy: 0.001)
        XCTAssertEqual(duplicate.frame.y, element.frame.y + 20, accuracy: 0.001)

        let selection = try XCTUnwrap(harness.controller.selection)
        XCTAssertEqual(selection.strokeIndices, IndexSet(integer: 1))
        XCTAssertEqual(selection.elementIDs, Set([duplicate.id]))
        XCTAssertFalse(selection.elementIDs.contains(element.id))
        XCTAssertTrue(harness.undoManager.canUndo)

        harness.undoManager.undo()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 1)
        XCTAssertEqual(harness.store.elements, [element].zOrderMaterialized())
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "A mixed stroke-and-element duplicate must register exactly one undo entry"
        )
        XCTAssertTrue(harness.undoManager.canRedo)

        harness.undoManager.redo()

        XCTAssertEqual(harness.canvasView.drawing.strokes.count, 2)
        XCTAssertEqual(harness.store.elements.count, 2)
        XCTAssertTrue(harness.store.elements.contains(where: { $0.id == duplicate.id }))
        XCTAssertFalse(harness.undoManager.canRedo)
    }

    func testDuplicatePreservesLayerPlacement() throws {
        var element = makeElement(
            frame: CanvasRect(x: 60, y: 20, width: 30, height: 30)
        )
        element.layerPlacement = .aboveInk
        let harness = makeHarness(strokes: [], elements: [element])
        harness.controller.selectElement(id: element.id)

        harness.controller.duplicateSelection()

        let duplicate = try XCTUnwrap(
            harness.store.elements.first(where: { $0.id != element.id })
        )
        XCTAssertEqual(duplicate.layerPlacement, .aboveInk)
    }

    func testExternalDrawingChangeClearsSelection() {
        let harness = makeHarness(
            strokes: [makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])],
            elements: []
        )
        harness.controller.beginCapture(at: CGPoint(x: 0, y: 0), mode: .boxed)
        harness.controller.extendCapture(to: CGPoint(x: 100, y: 100))
        harness.controller.endCapture()
        XCTAssertNotNil(harness.controller.selection)

        harness.controller.externalDrawingDidChange()

        XCTAssertNil(harness.controller.selection)
        XCTAssertNil(harness.controller.selectionBounds)
    }

    func testOpenFreeformCaptureSelectsEnclosedStroke() throws {
        let harness = makeHarness(
            strokes: [
                makeStroke(
                    locations: [
                        CGPoint(x: 10, y: 10),
                        CGPoint(x: 20, y: 20),
                        CGPoint(x: 30, y: 18),
                    ]
                ),
                makeStroke(
                    locations: [CGPoint(x: 200, y: 200), CGPoint(x: 220, y: 220)]
                ),
            ],
            elements: []
        )

        harness.controller.beginCapture(at: CGPoint(x: -10, y: -10), mode: .freeform)
        harness.controller.extendCapture(to: CGPoint(x: 60, y: -10))
        harness.controller.extendCapture(to: CGPoint(x: 25, y: 60))
        harness.controller.endCapture()

        let selection = try XCTUnwrap(harness.controller.selection)
        XCTAssertEqual(selection.strokeIndices, IndexSet(integer: 0))
        XCTAssertTrue(selection.elementIDs.isEmpty)
    }

    private func selectMixedContent(in harness: Harness) {
        harness.controller.beginCapture(at: CGPoint(x: 0, y: 0), mode: .boxed)
        harness.controller.extendCapture(to: CGPoint(x: 110, y: 80))
        harness.controller.endCapture()
    }

    private func makeHarness(strokes: [PKStroke], elements: [CanvasElement]) -> Harness {
        let canvasView = PKCanvasView()
        canvasView.drawing = PKDrawing(strokes: strokes)

        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView

        let undoManager = UndoManager()
        let store = CanvasElementsStore()
        store.canvasReference = canvasReference
        store.undoManagerOverride = undoManager
        store.hydrate(elements)

        let controller = CanvasSelectionController()
        controller.canvasReference = canvasReference
        controller.elementsStore = store
        undoManager.removeAllActions()

        return Harness(
            canvasView: canvasView,
            canvasReference: canvasReference,
            store: store,
            undoManager: undoManager,
            controller: controller
        )
    }

    private func makeStroke(locations: [CGPoint]) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.1,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
    }

    private func makeElement(frame: CanvasRect, rotation: Double = 0) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Selected",
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame,
            rotation: rotation
        )
    }

    private func makeShapeElement(frame: CanvasRect) -> CanvasElement {
        CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0),
                            CanvasPoint(x: 1, y: 1),
                        ],
                        isClosed: false
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 4
                )
            ),
            frame: frame
        )
    }

    private func makeImageElement(frame: CanvasRect) -> CanvasElement {
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: "assets/test.jpg",
                    originalPixelSize: CanvasSize(width: 800, height: 600)
                )
            ),
            frame: frame
        )
    }

    private func assertStrokeTransform(
        _ stroke: PKStroke,
        x: CGFloat,
        y: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(stroke.transform.tx, x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(stroke.transform.ty, y, accuracy: 0.001, file: file, line: line)
    }

    private struct Harness {
        let canvasView: PKCanvasView
        let canvasReference: NoteCanvasReference
        let store: CanvasElementsStore
        let undoManager: UndoManager
        let controller: CanvasSelectionController
    }

    private final class DrawingChangeCounter {
        var value = 0
    }
}
