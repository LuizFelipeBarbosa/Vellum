import Foundation
import PencilKit
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class SelectionTransformTests: XCTestCase {
    func testPinchScaleTwoXKeepsSelectionCenterInvariant() throws {
        let harness = CanvasHarness.make(
            strokes: [
                CanvasFixtures.makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 50, y: 40)]
                ),
            ],
            elements: []
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        let originalBounds = try XCTUnwrap(harness.controller.selectionBounds)

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 2, height: 2),
            rotation: 0
        )
        harness.controller.endHandleDrag()

        let transformedBounds = harness.canvasView.drawing.strokes[0].renderBounds
        XCTAssertEqual(transformedBounds.midX, originalBounds.midX, accuracy: 0.5)
        XCTAssertEqual(transformedBounds.midY, originalBounds.midY, accuracy: 0.5)

        let selectionBounds = try XCTUnwrap(harness.controller.selectionBounds)
        // renderBounds pads by ink width, which does not scale linearly with the
        // geometry transform — allow a few points around the doubled size.
        XCTAssertEqual(selectionBounds.width, originalBounds.width * 2, accuracy: 3)
        XCTAssertEqual(selectionBounds.height, originalBounds.height * 2, accuracy: 3)
    }

    func testCornerDragScaleTwoXPinsTheOppositeCorner() throws {
        let element = CanvasFixtures.makeTextElement(
            frame: CanvasRect(x: 30, y: 40, width: 60, height: 36)
        )
        let harness = CanvasHarness.make(strokes: [], elements: [element])
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 120, y: 120))
        let originalBounds = try XCTUnwrap(harness.controller.selectionBounds)

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 2, height: 2),
            rotation: 0,
            anchor: .zero
        )
        harness.controller.endHandleDrag()

        let transformedBounds = try XCTUnwrap(harness.controller.selectionBounds)
        XCTAssertEqual(transformedBounds.minX, originalBounds.minX, accuracy: 0.000_001)
        XCTAssertEqual(transformedBounds.minY, originalBounds.minY, accuracy: 0.000_001)
        XCTAssertEqual(
            transformedBounds.width,
            originalBounds.width * 2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            transformedBounds.height,
            originalBounds.height * 2,
            accuracy: 0.000_001
        )
    }

    func testRotationNinetyDegreesUsesVerifiedCompositeOrder() throws {
        let originalRotation = 0.25
        let element = CanvasFixtures.makeTextElement(
            frame: CanvasRect(x: 70, y: 25, width: 30, height: 24),
            rotation: originalRotation
        )
        let harness = CanvasHarness.make(
            strokes: [
                CanvasFixtures.makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 45, y: 45)]
                ),
            ],
            elements: [element]
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 130, y: 90))
        let bounds = try XCTUnwrap(harness.controller.selectionBounds)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 1, height: 1),
            rotation: .pi / 2
        )
        harness.controller.endHandleDrag()

        let transformedElement = try XCTUnwrap(harness.store.elements.first)
        XCTAssertEqual(
            transformedElement.rotation,
            originalRotation + .pi / 2,
            accuracy: 0.000_001
        )

        // A quarter turn and nothing else: the linear part is exactly [0 1; -1 0] — no scale,
        // no shear, no mirror — and the selection center is the point it pivots about. Those
        // six numbers fix the transform completely without restating how it is composed.
        let actual = harness.canvasView.drawing.strokes[0].transform
        XCTAssertEqual(actual.a, 0, accuracy: 0.000_001)
        XCTAssertEqual(actual.b, 1, accuracy: 0.000_001)
        XCTAssertEqual(actual.c, -1, accuracy: 0.000_001)
        XCTAssertEqual(actual.d, 0, accuracy: 0.000_001)

        let pivoted = center.applying(actual)
        XCTAssertEqual(pivoted.x, center.x, accuracy: 0.000_001)
        XCTAssertEqual(pivoted.y, center.y, accuracy: 0.000_001)
    }

    func testShapeHandleTransformScalesFrameStrokeWidthAndRotation() throws {
        let originalRotation = 0.2
        let originalStrokeWidth = 6.0
        let element = makeShapeElement(
            frame: CanvasRect(x: 50, y: 40, width: 40, height: 20),
            rotation: originalRotation,
            strokeWidth: originalStrokeWidth
        )
        let harness = CanvasHarness.make(strokes: [], elements: [element])
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 150, y: 120))
        let scale = CGSize(width: 2, height: 1.5)
        let appliedRotation = Double.pi / 4
        let originalCenter = CGPoint(
            x: element.frame.x + element.frame.width / 2,
            y: element.frame.y + element.frame.height / 2
        )

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: scale,
            rotation: appliedRotation
        )
        harness.controller.endHandleDrag()

        let transformed = try XCTUnwrap(harness.store.elements.first)
        XCTAssertEqual(
            transformed.frame.width,
            element.frame.width * Double(scale.width),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            transformed.frame.height,
            element.frame.height * Double(scale.height),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            transformed.frame.x,
            Double(originalCenter.x) - transformed.frame.width / 2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            transformed.frame.y,
            Double(originalCenter.y) - transformed.frame.height / 2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            transformed.rotation,
            originalRotation + appliedRotation,
            accuracy: 0.000_001
        )
        guard case .shape(let shape) = transformed.content else {
            return XCTFail("Expected a shape element")
        }
        XCTAssertEqual(
            shape.strokeWidth,
            originalStrokeWidth * Double(min(scale.width, scale.height)),
            accuracy: 0.000_001
        )
    }

    func testRotatedElementCornerDragPinsTheAnchorInCanvasSpace() throws {
        let rotation = 0.4
        let factor: CGFloat = 1.5
        let element = CanvasFixtures.makeTextElement(
            frame: CanvasRect(x: 35, y: 45, width: 80, height: 48),
            rotation: rotation
        )
        let harness = CanvasHarness.make(strokes: [], elements: [element])
        harness.controller.selectElement(id: element.id)
        let originalFrame = CGRect(
            x: element.frame.x,
            y: element.frame.y,
            width: element.frame.width,
            height: element.frame.height
        )
        let originalAnchor = SelectionResizeMath.point(
            atUnit: .zero,
            in: originalFrame,
            rotation: rotation
        )

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: factor, height: factor),
            rotation: 0,
            anchor: .zero
        )
        harness.controller.endHandleDrag()

        let transformed = try XCTUnwrap(harness.store.elements.first)
        let transformedFrame = CGRect(
            x: transformed.frame.x,
            y: transformed.frame.y,
            width: transformed.frame.width,
            height: transformed.frame.height
        )
        let transformedAnchor = SelectionResizeMath.point(
            atUnit: .zero,
            in: transformedFrame,
            rotation: rotation
        )
        XCTAssertEqual(transformedAnchor.x, originalAnchor.x, accuracy: 0.000_001)
        XCTAssertEqual(transformedAnchor.y, originalAnchor.y, accuracy: 0.000_001)
        XCTAssertEqual(
            transformed.frame.width,
            element.frame.width * Double(factor),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            transformed.frame.height,
            element.frame.height * Double(factor),
            accuracy: 0.000_001
        )
    }

    func testMixedHandleTransformIsExactlyOneUndoStep() throws {
        let element = CanvasFixtures.makeTextElement(
            frame: CanvasRect(x: 65, y: 20, width: 32, height: 28),
            rotation: 0.2
        )
        let stroke = CanvasFixtures.makeStroke(
            locations: [CGPoint(x: 20, y: 20), CGPoint(x: 45, y: 45)]
        )
        let harness = CanvasHarness.make(strokes: [stroke], elements: [element])
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 130, y: 90))

        let originalTransform = harness.canvasView.drawing.strokes[0].transform
        let originalElement = try XCTUnwrap(harness.store.elements.first)

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 1.5, height: 0.8),
            rotation: .pi / 4
        )
        harness.controller.endHandleDrag()

        XCTAssertTrue(harness.undoManager.canUndo)
        XCTAssertNotEqual(harness.canvasView.drawing.strokes[0].transform, originalTransform)
        XCTAssertNotEqual(harness.store.elements.first, originalElement)

        harness.undoManager.undo()

        assertTransform(
            harness.canvasView.drawing.strokes[0].transform,
            equals: originalTransform
        )
        XCTAssertEqual(harness.store.elements, [originalElement])
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "A mixed transform must register one undo entry for drawing and elements"
        )
    }

    func testRestyleColorChangesOnlySelectedStrokeAndSurvivesDrawingRoundTrip() throws {
        let harness = CanvasHarness.make(
            strokes: [
                CanvasFixtures.makeStroke(
                    locations: [CGPoint(x: 20, y: 20), CGPoint(x: 50, y: 40)],
                    color: .black
                ),
                CanvasFixtures.makeStroke(
                    locations: [CGPoint(x: 250, y: 250), CGPoint(x: 280, y: 280)],
                    color: .blue
                ),
            ],
            elements: []
        )
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        let color = CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)

        harness.controller.restyleSelection(color: color, strokeWidth: nil)

        assertColor(harness.canvasView.drawing.strokes[0].ink.color, equals: color)
        assertUIColor(harness.canvasView.drawing.strokes[1].ink.color, equals: .blue)

        let data = PKDrawing(
            strokes: harness.canvasView.drawing.strokes
        ).dataRepresentation()
        let roundTripped = try PKDrawing(data: data)
        assertColor(roundTripped.strokes[0].ink.color, equals: color)
        assertUIColor(roundTripped.strokes[1].ink.color, equals: .blue)
    }

    func testRestyleWidthPreservesPointCountTransformAndCreationDate() throws {
        let creationDate = Date(timeIntervalSince1970: 1_234_567)
        let originalTransform = CGAffineTransform(translationX: 7, y: 9)
            .concatenating(CGAffineTransform(rotationAngle: 0.15))
        let stroke = CanvasFixtures.makeStroke(
            locations: [
                CGPoint(x: 20, y: 20),
                CGPoint(x: 35, y: 30),
                CGPoint(x: 50, y: 45),
            ],
            size: CGSize(width: 4, height: 6),
            transform: originalTransform,
            creationDate: creationDate
        )
        let harness = CanvasHarness.make(strokes: [stroke], elements: [])
        select(in: harness, from: CGPoint(x: -20, y: -20), to: CGPoint(x: 140, y: 140))
        let targetWidth = 13.0

        harness.controller.restyleSelection(color: nil, strokeWidth: targetWidth)

        let restyled = harness.canvasView.drawing.strokes[0]
        XCTAssertEqual(restyled.path.count, stroke.path.count)
        XCTAssertEqual(averageTipWidth(restyled), targetWidth, accuracy: 0.001)
        assertTransform(restyled.transform, equals: stroke.transform)
        XCTAssertEqual(restyled.path.creationDate, stroke.path.creationDate)
    }

    func testShapeRestyleAppliesColorAndWidthIndependently() throws {
        let originalColor = CodableColor(red: 0.1, green: 0.2, blue: 0.3)
        var element = makeShapeElement(
            frame: CanvasRect(x: 30, y: 30, width: 80, height: 60),
            strokeWidth: 6
        )
        guard case .shape(var originalShape) = element.content else {
            return XCTFail("Expected a shape element")
        }
        originalShape.strokeColor = originalColor
        element.content = .shape(originalShape)
        let harness = CanvasHarness.make(strokes: [], elements: [element])
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 150, y: 120))

        harness.controller.restyleSelection(color: nil, strokeWidth: 11)

        let widthRestyled = try XCTUnwrap(harness.store.elements.first)
        guard case .shape(let widthRestyledShape) = widthRestyled.content else {
            return XCTFail("Expected a shape element")
        }
        XCTAssertEqual(widthRestyledShape.strokeColor, originalColor)
        XCTAssertEqual(widthRestyledShape.strokeWidth, 11)

        let updatedColor = CodableColor(red: 0.7, green: 0.5, blue: 0.2)
        harness.controller.restyleSelection(color: updatedColor, strokeWidth: nil)

        let colorRestyled = try XCTUnwrap(harness.store.elements.first)
        guard case .shape(let colorRestyledShape) = colorRestyled.content else {
            return XCTFail("Expected a shape element")
        }
        XCTAssertEqual(colorRestyledShape.strokeColor, updatedColor)
        XCTAssertEqual(colorRestyledShape.strokeWidth, 11)
    }

    func testLiveTransformFollowsAMoveDragForSelectedElementsOnly() throws {
        let selected = makeShapeElement(frame: CanvasRect(x: 20, y: 20, width: 60, height: 40))
        let untouched = makeShapeElement(
            frame: CanvasRect(x: 300, y: 300, width: 60, height: 40)
        )
        let harness = CanvasHarness.make(strokes: [], elements: [selected, untouched])
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 120, y: 120))

        harness.controller.beginMoveDrag()
        harness.controller.setDragTranslation(CGSize(width: 35, height: -18))

        assertTransform(
            harness.controller.liveTransform(forElementWith: selected.id),
            equals: CGAffineTransform(translationX: 35, y: -18)
        )
        assertTransform(
            harness.controller.liveTransform(forElementWith: untouched.id),
            equals: .identity
        )
    }

    func testLiveTransformScalesAboutTheCenterDuringAPinch() throws {
        let element = makeShapeElement(frame: CanvasRect(x: 20, y: 20, width: 60, height: 40))
        let harness = CanvasHarness.make(strokes: [], elements: [element])
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 120, y: 120))
        let bounds = try XCTUnwrap(harness.controller.selectionBounds)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 2, height: 2),
            rotation: 0
        )

        // The preview must pin the same center the commit does, or the shape would jump on drop.
        let transform = harness.controller.liveTransform(forElementWith: element.id)
        let movedCenter = center.applying(transform)
        XCTAssertEqual(movedCenter.x, center.x, accuracy: 0.001)
        XCTAssertEqual(movedCenter.y, center.y, accuracy: 0.001)

        let corner = CGPoint(x: bounds.minX, y: bounds.minY).applying(transform)
        XCTAssertEqual(corner.x, center.x - bounds.width, accuracy: 0.001)
        XCTAssertEqual(corner.y, center.y - bounds.height, accuracy: 0.001)
    }

    func testLiveTransformPinsTheAnchorDuringAHandleDrag() throws {
        let element = makeShapeElement(
            frame: CanvasRect(x: 20, y: 30, width: 60, height: 40)
        )
        let harness = CanvasHarness.make(strokes: [], elements: [element])
        harness.controller.selectElement(id: element.id)
        let bounds = try XCTUnwrap(harness.controller.selectionBounds)
        let anchor = bounds.origin
        let oppositeCorner = CGPoint(x: bounds.maxX, y: bounds.maxY)

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 2, height: 2),
            rotation: 0,
            anchor: .zero
        )

        let transform = harness.controller.liveTransform(forElementWith: element.id)
        let transformedAnchor = anchor.applying(transform)
        XCTAssertEqual(transformedAnchor.x, anchor.x, accuracy: 0.000_001)
        XCTAssertEqual(transformedAnchor.y, anchor.y, accuracy: 0.000_001)

        let transformedOppositeCorner = oppositeCorner.applying(transform)
        XCTAssertEqual(
            transformedOppositeCorner.x,
            anchor.x + bounds.width * 2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            transformedOppositeCorner.y,
            anchor.y + bounds.height * 2,
            accuracy: 0.000_001
        )
    }

    func testPreviewMatchesCommitForARotatedAnchoredDrag() throws {
        let element = makeShapeElement(
            frame: CanvasRect(x: 30, y: 40, width: 70, height: 45),
            rotation: 0.4
        )
        let harness = CanvasHarness.make(strokes: [], elements: [element])
        harness.controller.selectElement(id: element.id)
        let originalCenter = CGPoint(
            x: element.frame.x + element.frame.width / 2,
            y: element.frame.y + element.frame.height / 2
        )

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: 1.5, height: 1.5),
            rotation: 0,
            anchor: .zero
        )
        let previewCenter = originalCenter.applying(
            harness.controller.liveTransform(forElementWith: element.id)
        )
        harness.controller.endHandleDrag()

        let transformed = try XCTUnwrap(harness.store.elements.first)
        let committedCenter = CGPoint(
            x: transformed.frame.x + transformed.frame.width / 2,
            y: transformed.frame.y + transformed.frame.height / 2
        )
        XCTAssertEqual(previewCenter.x, committedCenter.x, accuracy: 0.000_001)
        XCTAssertEqual(previewCenter.y, committedCenter.y, accuracy: 0.000_001)
    }

    func testAnchoredShrinkNeverFlipsAndFloorsAtMinimumExtent() throws {
        let element = CanvasFixtures.makeTextElement(
            frame: CanvasRect(x: 30, y: 40, width: 60, height: 36)
        )
        let harness = CanvasHarness.make(strokes: [], elements: [element])
        harness.controller.selectElement(id: element.id)
        let originalBounds = try XCTUnwrap(harness.controller.selectionBounds)
        let anchor = originalBounds.origin

        harness.controller.beginHandleDrag()
        harness.controller.setHandleTransform(
            scale: CGSize(width: -0.5, height: -0.5),
            rotation: 0,
            anchor: .zero
        )
        harness.controller.endHandleDrag()

        let transformedBounds = try XCTUnwrap(harness.controller.selectionBounds)
        XCTAssertGreaterThanOrEqual(
            transformedBounds.width,
            SelectionResizeMath.minimumExtent
        )
        XCTAssertGreaterThanOrEqual(
            transformedBounds.height,
            SelectionResizeMath.minimumExtent
        )
        XCTAssertGreaterThan(transformedBounds.width, 0)
        XCTAssertGreaterThan(transformedBounds.height, 0)
        XCTAssertEqual(transformedBounds.minX, anchor.x, accuracy: 0.000_001)
        XCTAssertEqual(transformedBounds.minY, anchor.y, accuracy: 0.000_001)
        XCTAssertGreaterThan(transformedBounds.maxX, anchor.x)
        XCTAssertGreaterThan(transformedBounds.maxY, anchor.y)
    }

    func testHandleAnchorTableMatchesOppositeCorner() {
        XCTAssertEqual(SelectionHandle.bottomRight.anchorUnit, CGPoint(x: 0, y: 0))
        XCTAssertEqual(SelectionHandle.topLeft.anchorUnit, CGPoint(x: 1, y: 1))
        XCTAssertEqual(SelectionHandle.right.anchorUnit, CGPoint(x: 0, y: 0.5))
        XCTAssertEqual(SelectionHandle.top.anchorUnit, CGPoint(x: 0.5, y: 1))
        XCTAssertEqual(SelectionHandle.rotation.anchorUnit, CGPoint(x: 0.5, y: 0.5))
    }

    func testDraggingAShapeSnapsItToThePageLattice() throws {
        // A horizontal line: its frame is inflated to a minimum extent, so the line itself sits
        // at the middle of the frame, not at its top edge.
        let line = makeLineShape(from: CGPoint(x: 30, y: 100), to: CGPoint(x: 150, y: 100))
        let harness = CanvasHarness.make(strokes: [], elements: [line])
        harness.controller.snapGrid = { _ in
            ShapeSnapGrid(origin: .zero, spacing: 24, snapsX: true, snapsY: true)
        }
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 200))

        // Dropping the line at y = 141 puts it 3pt from the rule at 144, inside the tolerance.
        harness.controller.beginMoveDrag()
        harness.controller.setDragTranslation(CGSize(width: 20, height: 41))

        XCTAssertEqual(harness.controller.dragTranslation.height, 44, accuracy: 0.001)
        XCTAssertEqual(harness.controller.dragTranslation.width, 18, accuracy: 0.001)

        harness.controller.endMoveDrag()
        let moved = try XCTUnwrap(harness.store.elements.first)
        let drawn = ShapeGeometry.path(
            for: try XCTUnwrap(shapeContent(of: moved)),
            in: moved.frame,
            rotation: moved.rotation
        ).boundingBox
        XCTAssertEqual(drawn.minY, 144, accuracy: 0.001)
        XCTAssertEqual(drawn.minX, 48, accuracy: 0.001)
    }

    func testDraggingAShapeFarFromTheLatticeIsNotPulled() {
        let line = makeLineShape(from: CGPoint(x: 30, y: 100), to: CGPoint(x: 150, y: 100))
        let harness = CanvasHarness.make(strokes: [], elements: [line])
        harness.controller.snapGrid = { _ in
            ShapeSnapGrid(origin: .zero, spacing: 24, snapsX: true, snapsY: true)
        }
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 200))

        // 132 sits midway between the rules at 120 and 144, so neither is within the 7.2pt
        // tolerance and the line stays exactly where it was dropped.
        harness.controller.beginMoveDrag()
        harness.controller.setDragTranslation(CGSize(width: 0, height: 32))

        XCTAssertEqual(harness.controller.dragTranslation.height, 32, accuracy: 0.001)
    }

    func testDraggingInkOnlyIsNeverSnapped() {
        let harness = CanvasHarness.make(
            strokes: [CanvasFixtures.makeStroke(locations: [CGPoint(x: 20, y: 20), CGPoint(x: 50, y: 40)])],
            elements: []
        )
        harness.controller.snapGrid = { _ in
            ShapeSnapGrid(origin: .zero, spacing: 24, snapsX: true, snapsY: true)
        }
        select(in: harness, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))

        harness.controller.beginMoveDrag()
        harness.controller.setDragTranslation(CGSize(width: 27, height: 27))

        XCTAssertEqual(harness.controller.dragTranslation.width, 27, accuracy: 0.001)
        XCTAssertEqual(harness.controller.dragTranslation.height, 27, accuracy: 0.001)
    }

    func testLiveTransformIsIdentityWithoutASelection() {
        let element = makeShapeElement(frame: CanvasRect(x: 20, y: 20, width: 60, height: 40))
        let harness = CanvasHarness.make(strokes: [], elements: [element])

        assertTransform(
            harness.controller.liveTransform(forElementWith: element.id),
            equals: .identity
        )
    }

    private func select(
        in harness: CanvasHarness,
        from start: CGPoint,
        to end: CGPoint
    ) {
        harness.controller.beginCapture(at: start, mode: .boxed)
        harness.controller.extendCapture(to: end)
        harness.controller.endCapture()
    }



    /// A line built the way the recognizer builds one, so its frame carries the same minimum
    /// extent inflation a real horizontal line has.
    private func makeLineShape(from start: CGPoint, to end: CGPoint) -> CanvasElement {
        let built = ShapeElementBuilder.element(
            from: .polyline(vertices: [start, end], isClosed: false),
            strokeColor: CodableColor(red: 0, green: 0, blue: 0),
            strokeWidth: 4
        )
        return CanvasElement(
            content: .shape(built.content),
            frame: built.frame,
            rotation: built.rotation
        )
    }

    private func shapeContent(of element: CanvasElement) -> ShapeContent? {
        guard case .shape(let content) = element.content else { return nil }
        return content
    }

    private func makeShapeElement(
        frame: CanvasRect,
        rotation: Double = 0,
        strokeWidth: Double = 6
    ) -> CanvasElement {
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
                    strokeWidth: strokeWidth
                )
            ),
            frame: frame,
            rotation: rotation
        )
    }

    private func averageTipWidth(_ stroke: PKStroke) -> Double {
        let total = stroke.path.reduce(CGFloat.zero) { $0 + $1.size.width }
        return Double(total / CGFloat(stroke.path.count))
    }

    private func assertTransform(
        _ actual: CGAffineTransform,
        equals expected: CGAffineTransform,
        accuracy: CGFloat = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.a, expected.a, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.c, expected.c, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.d, expected.d, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.tx, expected.tx, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.ty, expected.ty, accuracy: accuracy, file: file, line: line)
    }

    private func assertColor(
        _ actual: UIColor,
        equals expected: CodableColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(
            actual.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            file: file,
            line: line
        )
        XCTAssertEqual(red, CGFloat(expected.red), accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(green, CGFloat(expected.green), accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(blue, CGFloat(expected.blue), accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(alpha, CGFloat(expected.alpha), accuracy: 0.01, file: file, line: line)
    }

    private func assertUIColor(
        _ actual: UIColor,
        equals expected: UIColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualComponents = actual.cgColor.components ?? []
        let expectedComponents = expected.cgColor.components ?? []
        XCTAssertEqual(actualComponents.count, expectedComponents.count, file: file, line: line)
        for (actual, expected) in zip(actualComponents, expectedComponents) {
            XCTAssertEqual(actual, expected, accuracy: 0.01, file: file, line: line)
        }
    }

}
