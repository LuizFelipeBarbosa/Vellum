import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class SelectionActionStripPositionTests: XCTestCase {
    func testPositionPrefersAboveWhenBothPlacementsFit() {
        let avoidRect = CGRect(x: 200, y: 200, width: 100, height: 80)
        let stripSize = CGSize(width: 120, height: 40)
        let viewportSize = CGSize(width: 600, height: 600)

        let position = SelectionActionStripView.position(
            avoiding: avoidRect,
            stripSize: stripSize,
            in: viewportSize
        )
        let stripFrame = frame(centeredAt: position, size: stripSize)

        // The 40pt-tall strip is centered 12pt above the avoidance rect's top edge:
        // 200 - 12 - 20 for the center, 200 - 12 for its bottom.
        XCTAssertEqual(position.y, 168, accuracy: 0.001)
        XCTAssertEqual(stripFrame.maxY, 188, accuracy: 0.001)
        XCTAssertFalse(stripFrame.intersects(avoidRect))
    }

    func testPositionFallsBelowNearViewportTop() {
        let avoidRect = CGRect(x: 200, y: 20, width: 100, height: 80)
        let stripSize = CGSize(width: 120, height: 40)
        let viewportSize = CGSize(width: 600, height: 600)

        let position = SelectionActionStripView.position(
            avoiding: avoidRect,
            stripSize: stripSize,
            in: viewportSize
        )
        let stripFrame = frame(centeredAt: position, size: stripSize)

        XCTAssertGreaterThanOrEqual(stripFrame.minY, avoidRect.maxY)
        XCTAssertFalse(stripFrame.intersects(avoidRect))
    }

    func testPositionAvoidsTopInsetForSelectionSpanningViewportTop() {
        let avoidRect = CGRect(x: 100, y: -50, width: 300, height: 150)
        let stripSize = CGSize(width: 120, height: 40)
        let viewportSize = CGSize(width: 600, height: 600)
        let topInset: CGFloat = 60

        let position = SelectionActionStripView.position(
            avoiding: avoidRect,
            stripSize: stripSize,
            in: viewportSize,
            topInset: topInset
        )
        let stripFrame = frame(centeredAt: position, size: stripSize)

        XCTAssertGreaterThanOrEqual(stripFrame.minY, topInset + 8)
        XCTAssertGreaterThanOrEqual(stripFrame.minY, avoidRect.maxY)
        XCTAssertFalse(stripFrame.intersects(avoidRect))
    }

    func testPositionWithoutTopInsetPreservesExistingPlacement() {
        let avoidRect = CGRect(x: 100, y: -50, width: 300, height: 150)
        let stripSize = CGSize(width: 120, height: 40)
        let viewportSize = CGSize(width: 600, height: 600)

        let position = SelectionActionStripView.position(
            avoiding: avoidRect,
            stripSize: stripSize,
            in: viewportSize
        )

        // The selection starts above the viewport, so only the below placement fits: the
        // strip centers 12pt under the rect's bottom edge, 100 + 12 + 20.
        XCTAssertEqual(position.y, 132, accuracy: 0.001)
    }

    func testPositionPinsInsideViewportBottomWhenNeitherPlacementFits() {
        let avoidRect = CGRect(x: 100, y: 0, width: 300, height: 600)
        let stripSize = CGSize(width: 120, height: 40)
        let viewportSize = CGSize(width: 600, height: 600)

        let position = SelectionActionStripView.position(
            avoiding: avoidRect,
            stripSize: stripSize,
            in: viewportSize
        )
        let stripFrame = frame(centeredAt: position, size: stripSize)

        XCTAssertLessThanOrEqual(stripFrame.maxY, viewportSize.height - 8)
        XCTAssertEqual(
            position.y,
            viewportSize.height - 8 - stripSize.height / 2,
            accuracy: 0.001
        )
    }

    func testPositionClampsHorizontallyAndCentersInTinyViewport() {
        let stripSize = CGSize(width: 120, height: 40)
        let viewportSize = CGSize(width: 600, height: 600)

        let leftPosition = SelectionActionStripView.position(
            avoiding: CGRect(x: -20, y: 200, width: 10, height: 40),
            stripSize: stripSize,
            in: viewportSize
        )
        XCTAssertGreaterThanOrEqual(
            frame(centeredAt: leftPosition, size: stripSize).minX,
            8
        )

        let rightPosition = SelectionActionStripView.position(
            avoiding: CGRect(x: 610, y: 200, width: 10, height: 40),
            stripSize: stripSize,
            in: viewportSize
        )
        XCTAssertLessThanOrEqual(
            frame(centeredAt: rightPosition, size: stripSize).maxX,
            viewportSize.width - 8
        )

        let tinyViewportSize = CGSize(width: 100, height: 50)
        let tinyPosition = SelectionActionStripView.position(
            avoiding: CGRect(x: 20, y: 10, width: 60, height: 30),
            stripSize: stripSize,
            in: tinyViewportSize
        )
        XCTAssertEqual(tinyPosition.x, tinyViewportSize.width / 2, accuracy: 0.001)
        XCTAssertEqual(tinyPosition.y, tinyViewportSize.height / 2, accuracy: 0.001)
    }

    func testNonPinnedPlacementsNeverIntersectAvoidanceRectAcrossViewport() {
        assertNonPinnedPlacements(topInset: 0)
    }

    func testNonPinnedPlacementsRespectTopInsetAcrossViewport() {
        assertNonPinnedPlacements(topInset: 60)
    }

    func testUnrotatedSelectionAvoidsResizeAndRotationHandleChrome() throws {
        let element = CanvasFixtures.makeTextElement(
            frame: CanvasRect(x: 100, y: 200, width: 120, height: 60)
        )
        let harness = CanvasHarness.make(elements: [element])
        harness.controller.selectElement(id: element.id)

        let selectionBounds = try XCTUnwrap(harness.controller.selectionBounds)
        let avoidanceBounds = try XCTUnwrap(harness.controller.stripAvoidanceBounds)

        // The 100,200 120x60 selection grows by half a 28pt resize hit target on every side
        // (86,186 148x88) and then up to swallow the 32pt rotation target, whose center sits
        // 28pt above the top edge (144,156 32x32). Pinned to numbers so a change to any of
        // the three handle sizes has to be re-stated here.
        XCTAssertEqual(selectionBounds, CGRect(x: 100, y: 200, width: 120, height: 60))
        assertEqual(avoidanceBounds, CGRect(x: 86, y: 156, width: 148, height: 118))
    }

    func testAvoidanceBoundsContainsEveryHandleHitRect() throws {
        let element = CanvasFixtures.makeTextElement(
            frame: CanvasRect(x: 100, y: 200, width: 120, height: 60)
        )
        let harness = CanvasHarness.make(elements: [element])
        harness.controller.selectElement(id: element.id)

        let selectionBounds = try XCTUnwrap(harness.controller.selectionBounds)
        let avoidanceBounds = try XCTUnwrap(harness.controller.stripAvoidanceBounds)
        let resizeHitSize = SelectionHandleGeometry.resizeHitSize
        let resizeHitRectSize = CGSize(width: resizeHitSize, height: resizeHitSize)
        let resizeHandleCenters = [
            CGPoint(x: selectionBounds.minX, y: selectionBounds.minY),
            CGPoint(x: selectionBounds.maxX, y: selectionBounds.minY),
            CGPoint(x: selectionBounds.minX, y: selectionBounds.maxY),
            CGPoint(x: selectionBounds.maxX, y: selectionBounds.maxY),
        ]
        let resizeHitRects = resizeHandleCenters.map {
            frame(centeredAt: $0, size: resizeHitRectSize)
        }
        let rotationHitSize = SelectionHandleGeometry.rotationHitSize
        let rotationHitRect = frame(
            centeredAt: CGPoint(
                x: selectionBounds.midX,
                y: selectionBounds.minY - SelectionHandleGeometry.rotationOffset
            ),
            size: CGSize(width: rotationHitSize, height: rotationHitSize)
        )

        for hitRect in resizeHitRects + [rotationHitRect] {
            XCTAssertTrue(
                avoidanceBounds.contains(hitRect),
                "Avoidance bounds \(avoidanceBounds) do not contain handle hit rect \(hitRect)"
            )
        }
    }

    func testRotatedSelectionAvoidsPaintedBoundingBox() throws {
        let element = CanvasFixtures.makeTextElement(
            frame: CanvasRect(x: 100, y: 200, width: 200, height: 50),
            rotation: .pi / 4
        )
        let harness = CanvasHarness.make(elements: [element])
        harness.controller.selectElement(id: element.id)

        let selectionBounds = try XCTUnwrap(harness.controller.selectionBounds)
        let avoidanceBounds = try XCTUnwrap(harness.controller.stripAvoidanceBounds)
        let resizeHitSize = SelectionHandleGeometry.resizeHitSize
        let rotationHitSize = SelectionHandleGeometry.rotationHitSize
        let rotationCenter = CGPoint(
            x: selectionBounds.midX,
            y: selectionBounds.minY - SelectionHandleGeometry.rotationOffset
        )
        let handleBounds = selectionBounds
            .insetBy(dx: -resizeHitSize / 2, dy: -resizeHitSize / 2)
            .union(
                frame(
                    centeredAt: rotationCenter,
                    size: CGSize(width: rotationHitSize, height: rotationHitSize)
                )
            )
        let expected = handleBounds.union(element.rotatedBoundingBox)

        assertEqual(avoidanceBounds, expected)
        XCTAssertGreaterThan(avoidanceBounds.height, handleBounds.height)
    }

    func testNoSelectionHasNoStripAvoidanceBounds() {
        let harness = CanvasHarness.make(elements: [])

        XCTAssertNil(harness.controller.stripAvoidanceBounds)
    }

    private func assertNonPinnedPlacements(topInset: CGFloat) {
        let viewportSize = CGSize(width: 500, height: 400)
        let stripSize = CGSize(width: 120, height: 40)
        let margin: CGFloat = 8
        let gap: CGFloat = 12
        let originsX: [CGFloat] = [0, 20, 190, 380, 460]
        let originsY: [CGFloat] = [0, 20, 100, 260, 360]
        let sizes = [
            CGSize(width: 40, height: 40),
            CGSize(width: 120, height: 100),
        ]

        for originX in originsX {
            for originY in originsY {
                for size in sizes {
                    let avoidRect = CGRect(
                        x: originX,
                        y: originY,
                        width: size.width,
                        height: size.height
                    )
                    let aboveFits =
                        avoidRect.minY - gap - stripSize.height >= margin + topInset
                    let belowFits =
                        avoidRect.maxY + gap + stripSize.height <= viewportSize.height - margin
                    guard aboveFits || belowFits else { continue }

                    let position = SelectionActionStripView.position(
                        avoiding: avoidRect,
                        stripSize: stripSize,
                        in: viewportSize,
                        topInset: topInset
                    )
                    let stripFrame = frame(centeredAt: position, size: stripSize)

                    XCTAssertFalse(
                        stripFrame.intersects(avoidRect),
                        "Strip \(stripFrame) intersects avoidance rect \(avoidRect)"
                    )
                    if aboveFits {
                        XCTAssertGreaterThanOrEqual(
                            stripFrame.minY,
                            topInset + margin,
                            "Strip \(stripFrame) covers top inset \(topInset)"
                        )
                    } else {
                        XCTAssertGreaterThanOrEqual(
                            stripFrame.minY,
                            avoidRect.maxY,
                            "Strip \(stripFrame) is not below avoidance rect \(avoidRect)"
                        )
                    }
                }
            }
        }
    }

    private func frame(centeredAt point: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func assertEqual(
        _ actual: CGRect,
        _ expected: CGRect,
        accuracy: CGFloat = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }


}
