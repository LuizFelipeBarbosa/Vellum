import Foundation
import PencilKit
import SwiftUI
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class ShapeEraserTests: XCTestCase {
    func testPartialEraserDragRemovesIntersectedShapeAndLeavesOtherShape() {
        let hitShape = makePolylineShape(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 40)
        )
        let untouchedShape = makePolylineShape(
            frame: CanvasRect(x: 100, y: 300, width: 120, height: 40)
        )
        let harness = makeHarness(
            elements: [hitShape, untouchedShape],
            eraserConfig: EraserConfig(mode: .partial, width: 20)
        )

        harness.eraser.dragBegan()
        for x in stride(from: CGFloat(100), through: 220, by: 20) {
            harness.eraser.dragSample(at: CGPoint(x: x, y: 120))
        }
        harness.eraser.dragEnded()

        XCTAssertFalse(harness.store.elements.contains { $0.id == hitShape.id })
        XCTAssertTrue(harness.store.elements.contains { $0.id == untouchedShape.id })
        XCTAssertEqual(harness.store.elements.count, 1)
        XCTAssertEqual(harness.undoManager.undoActionName, "Erase Shapes")
    }

    func testWholeStrokeDragErasesEllipseAndPolylineAsOneUndoStep() {
        let ellipse = makeEllipseShape(
            frame: CanvasRect(x: 80, y: 100, width: 120, height: 80)
        )
        let polyline = makePolylineShape(
            frame: CanvasRect(x: 260, y: 100, width: 120, height: 40)
        )
        let originalElements = [ellipse, polyline]
        let harness = makeHarness(
            elements: originalElements,
            eraserConfig: EraserConfig(mode: .wholeStroke, width: 20)
        )

        harness.eraser.dragBegan()
        harness.eraser.dragSample(at: CGPoint(x: 80, y: 140))
        harness.eraser.dragSample(at: CGPoint(x: 320, y: 120))
        harness.eraser.dragEnded()

        XCTAssertTrue(harness.store.elements.isEmpty)
        XCTAssertTrue(harness.undoManager.canUndo)
        XCTAssertEqual(harness.undoManager.undoActionName, "Erase Shapes")

        harness.undoManager.undo()

        XCTAssertEqual(harness.store.elements, originalElements)
        XCTAssertFalse(harness.undoManager.canUndo)
        XCTAssertTrue(harness.undoManager.canRedo)
    }

    func testDragRemovesShapeOnContactBeforeTheGestureEnds() {
        let shape = makePolylineShape(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 40)
        )
        let harness = makeHarness(
            elements: [shape],
            eraserConfig: EraserConfig(mode: .partial, width: 20)
        )

        harness.eraser.dragBegan()
        harness.eraser.dragSample(at: CGPoint(x: 160, y: 120))

        XCTAssertTrue(
            harness.store.elements.isEmpty,
            "shape was not erased until the pencil lifted"
        )
        XCTAssertFalse(
            harness.undoManager.canUndo,
            "undo must be registered once when the gesture ends, not per contact"
        )

        harness.eraser.dragEnded()

        XCTAssertEqual(harness.undoManager.undoActionName, "Erase Shapes")
        harness.undoManager.undo()
        XCTAssertEqual(harness.store.elements, [shape])
    }

    func testDisablingTheEraserMidDragStillRegistersUndoForWhatWasErased() {
        let shape = makePolylineShape(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 40)
        )
        let harness = makeHarness(
            elements: [shape],
            eraserConfig: EraserConfig(mode: .partial, width: 20)
        )

        harness.eraser.dragBegan()
        harness.eraser.dragSample(at: CGPoint(x: 160, y: 120))
        XCTAssertTrue(harness.store.elements.isEmpty)

        harness.eraser.isEnabled = false

        XCTAssertEqual(harness.undoManager.undoActionName, "Erase Shapes")
        harness.undoManager.undo()
        XCTAssertEqual(harness.store.elements, [shape])
    }

    func testNearMissDoesNotRemoveShapeOrRegisterUndo() {
        let shape = makePolylineShape(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 40)
        )
        let harness = makeHarness(
            elements: [shape],
            eraserConfig: EraserConfig(mode: .partial, width: 8)
        )

        harness.eraser.dragBegan()
        for x in stride(from: CGFloat(110), through: 210, by: 20) {
            harness.eraser.dragSample(at: CGPoint(x: x, y: 126))
        }
        harness.eraser.dragEnded()

        XCTAssertEqual(harness.store.elements, [shape])
        XCTAssertFalse(harness.undoManager.canUndo)
    }

    func testDisabledSurfaceDoesNotEraseOrRegisterUndo() {
        let shape = makeEllipseShape(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 80)
        )
        let harness = makeHarness(
            elements: [shape],
            eraserConfig: EraserConfig(mode: .partial, width: 20),
            isEnabled: false
        )

        harness.eraser.dragBegan()
        harness.eraser.dragSample(at: CGPoint(x: 100, y: 140))
        harness.eraser.dragEnded()

        XCTAssertEqual(harness.store.elements, [shape])
        XCTAssertFalse(harness.undoManager.canUndo)
    }

    func testFastSwipeInterpolatesAcrossAThinShape() {
        let shape = makePolylineShape(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 40)
        )
        let eraserConfig = EraserConfig(mode: .partial, width: 8)
        let harness = makeHarness(
            elements: [shape],
            eraserConfig: eraserConfig
        )
        let firstSample = CGPoint(x: 160, y: 80)
        let secondSample = CGPoint(x: 160, y: 160)
        let strokedPath = shapeHitPath(
            for: shape,
            eraserRadius: CGFloat(eraserConfig.width) / 2
        )
        XCTAssertFalse(strokedPath.contains(firstSample))
        XCTAssertFalse(strokedPath.contains(secondSample))
        XCTAssertTrue(strokedPath.contains(CGPoint(x: 160, y: 120)))

        harness.eraser.dragBegan()
        harness.eraser.dragSample(at: firstSample)
        harness.eraser.dragSample(at: secondSample)
        harness.eraser.dragEnded()

        XCTAssertTrue(harness.store.elements.isEmpty)
        XCTAssertEqual(harness.undoManager.undoActionName, "Erase Shapes")
    }

    func testTapOnShapeErasesInOneUndoStep() {
        let shape = makePolylineShape(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 40)
        )
        let harness = makeHarness(
            elements: [shape],
            eraserConfig: EraserConfig(mode: .partial, width: 8)
        )

        harness.eraser.tap(at: CGPoint(x: 160, y: 120))

        XCTAssertTrue(harness.store.elements.isEmpty)
        XCTAssertTrue(harness.undoManager.canUndo)
        XCTAssertEqual(harness.undoManager.undoActionName, "Erase Shapes")

        harness.undoManager.undo()

        XCTAssertEqual(harness.store.elements, [shape])
        XCTAssertFalse(harness.undoManager.canUndo)
    }

    func testTapOnEmptyCanvasDoesNothing() {
        let shape = makePolylineShape(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 40)
        )
        let harness = makeHarness(
            elements: [shape],
            eraserConfig: EraserConfig(mode: .partial, width: 8)
        )

        harness.eraser.tap(at: CGPoint(x: 160, y: 220))

        XCTAssertEqual(harness.store.elements, [shape])
        XCTAssertFalse(harness.undoManager.canUndo)
    }

    func testWideningTheEraserMidDragErasesAShapeTheNarrowTipMissed() {
        let shape = makePolylineShape(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 40)
        )
        let harness = makeHarness(
            elements: [shape],
            eraserConfig: EraserConfig(mode: .partial, width: 8)
        )
        let samplePoint = CGPoint(x: 160, y: 134)

        harness.eraser.dragBegan()
        harness.eraser.dragSample(at: samplePoint)
        XCTAssertEqual(harness.store.elements, [shape])

        harness.eraser.eraserConfig = EraserConfig(mode: .partial, width: 60)
        harness.eraser.dragSample(at: samplePoint)

        XCTAssertTrue(
            harness.store.elements.isEmpty,
            "the wider tip must be applied mid-drag, not left stale from the first sample"
        )
        harness.eraser.dragEnded()
        XCTAssertEqual(harness.undoManager.undoActionName, "Erase Shapes")
    }

    func testDragErasesARotatedShapeAwayFromItsUnrotatedFrame() {
        // Rotating the horizontal line a quarter turn stands it up outside its own frame,
        // so a swipe near the top of the rotated line must still register.
        let shape = makePolylineShape(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 40),
            rotation: .pi / 2
        )
        let harness = makeHarness(
            elements: [shape],
            eraserConfig: EraserConfig(mode: .partial, width: 20)
        )

        harness.eraser.dragBegan()
        for x in stride(from: CGFloat(120), through: 200, by: 20) {
            harness.eraser.dragSample(at: CGPoint(x: x, y: 70))
        }
        harness.eraser.dragEnded()

        XCTAssertTrue(harness.store.elements.isEmpty)
        XCTAssertEqual(harness.undoManager.undoActionName, "Erase Shapes")
    }

    func testHitTestPicksTheOverlappingShapeDrawnOnTop() {
        let frame = CanvasRect(x: 100, y: 100, width: 120, height: 40)
        let polyline = makePolylineShape(frame: frame)
        let ellipse = makeEllipseShape(frame: frame)
        let extraRadius: CGFloat = 12
        let sharedPoint = CGPoint(x: 100, y: 120)
        XCTAssertTrue(shapeHitPath(for: polyline, eraserRadius: extraRadius).contains(sharedPoint))
        XCTAssertTrue(shapeHitPath(for: ellipse, eraserRadius: extraRadius).contains(sharedPoint))

        let topOfPolyline = ShapeHitTester.hitTest(
            elements: [polyline, ellipse],
            at: sharedPoint,
            minimumHitWidth: 4,
            extraRadius: extraRadius
        )
        let topOfEllipse = ShapeHitTester.hitTest(
            elements: [ellipse, polyline],
            at: sharedPoint,
            minimumHitWidth: 4,
            extraRadius: extraRadius
        )

        XCTAssertEqual(
            topOfPolyline?.id,
            ellipse.id,
            "elements paint in array order, so the later one is on top and wins the tap"
        )
        XCTAssertEqual(topOfEllipse?.id, polyline.id)
    }

    private func makeHarness(
        elements: [CanvasElement],
        eraserConfig: EraserConfig,
        isEnabled: Bool = true
    ) -> Harness {
        let canvasCoordinator = PencilCanvasView.Coordinator(
            onDrawingChanged: { _ in },
            onViewportChanged: nil
        )
        let canvasView = PKCanvasView()
        canvasView.minimumZoomScale = 0.1
        canvasView.maximumZoomScale = 10
        canvasView.zoomScale = 1
        canvasView.delegate = canvasCoordinator
        let canvasReference = NoteCanvasReference()
        canvasReference.canvasView = canvasView
        let undoManager = UndoManager()
        let store = CanvasElementsStore()
        store.canvasReference = canvasReference
        store.undoManagerOverride = undoManager
        store.hydrate(elements)
        let surface = ShapeEraserSurface(
            canvasReference: canvasReference,
            elementsStore: store,
            eraserConfig: eraserConfig,
            isEnabled: isEnabled
        )
        let eraser = surface.makeCoordinator()
        eraser.syncInstallation()
        return Harness(
            canvasView: canvasView,
            canvasCoordinator: canvasCoordinator,
            store: store,
            undoManager: undoManager,
            eraser: eraser
        )
    }

    private func makePolylineShape(
        frame: CanvasRect,
        rotation: Double = 0
    ) -> CanvasElement {
        CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0.5),
                            CanvasPoint(x: 1, y: 0.5),
                        ],
                        isClosed: false
                    ),
                    strokeColor: ToolPreferences.default.pen.color,
                    strokeWidth: 4
                )
            ),
            frame: frame,
            rotation: rotation,
            layerPlacement: .belowInk
        )
    }

    private func makeEllipseShape(frame: CanvasRect) -> CanvasElement {
        CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .ellipse,
                    strokeColor: ToolPreferences.default.pen.color,
                    strokeWidth: 4
                )
            ),
            frame: frame,
            layerPlacement: .belowInk
        )
    }

    private func shapeHitPath(
        for element: CanvasElement,
        eraserRadius: CGFloat
    ) -> CGPath {
        guard case .shape(let content) = element.content else {
            XCTFail("Expected a shape element.")
            return CGMutablePath()
        }
        let path = ShapeGeometry.path(
            for: content,
            in: element.frame,
            rotation: element.rotation
        )
        return path.copy(
            strokingWithWidth: max(CGFloat(content.strokeWidth), 4) + eraserRadius,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        )
    }

    private struct Harness {
        let canvasView: PKCanvasView
        let canvasCoordinator: PencilCanvasView.Coordinator
        let store: CanvasElementsStore
        let undoManager: UndoManager
        let eraser: ShapeEraserSurface.Coordinator
    }
}
