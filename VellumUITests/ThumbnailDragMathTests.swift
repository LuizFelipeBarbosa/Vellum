import XCTest
@testable import Vellum
import VellumCore

@MainActor
final class ThumbnailDragMathTests: XCTestCase {
    func testProposedIndexClampsToRealPages() {
        let rowHeight: CGFloat = 100

        XCTAssertEqual(
            ThumbnailDragMath.proposedIndex(
                fingerPanelY: -40,
                contentOffsetY: 0,
                grabOffsetY: 10,
                rowHeight: rowHeight,
                pageCount: 4
            ),
            0
        )
        XCTAssertEqual(
            ThumbnailDragMath.proposedIndex(
                fingerPanelY: 10,
                contentOffsetY: 0,
                grabOffsetY: 10,
                rowHeight: rowHeight,
                pageCount: 4
            ),
            0
        )
        XCTAssertEqual(
            ThumbnailDragMath.proposedIndex(
                fingerPanelY: 600,
                contentOffsetY: 0,
                grabOffsetY: 10,
                rowHeight: rowHeight,
                pageCount: 4
            ),
            3
        )
        XCTAssertEqual(
            ThumbnailDragMath.proposedIndex(
                fingerPanelY: 410,
                contentOffsetY: 0,
                grabOffsetY: 10,
                rowHeight: rowHeight,
                pageCount: 4
            ),
            3,
            "The virtual cell at index 4 must never become a proposed index"
        )
    }

    func testDisplacementWhenDraggingDown() {
        let displacements = (0..<5).map {
            ThumbnailDragMath.displacement(
                forRow: $0,
                draggedIndex: 1,
                proposedIndex: 3,
                rowHeight: 100
            )
        }

        XCTAssertEqual(displacements, [0, 0, -100, -100, 0])
    }

    func testDisplacementWhenDraggingUp() {
        let displacements = (0..<5).map {
            ThumbnailDragMath.displacement(
                forRow: $0,
                draggedIndex: 3,
                proposedIndex: 1,
                rowHeight: 100
            )
        }

        XCTAssertEqual(displacements, [0, 100, 100, 0, 0])
    }

    func testDisplacementWhenProposedIndexIsUnchanged() {
        let displacements = (0..<5).map {
            ThumbnailDragMath.displacement(
                forRow: $0,
                draggedIndex: 2,
                proposedIndex: 2,
                rowHeight: 100
            )
        }

        XCTAssertEqual(displacements, [0, 0, 0, 0, 0])
    }

    func testDropDestinationUsesListMoveSemantics() {
        XCTAssertEqual(
            ThumbnailDragMath.dropDestination(
                draggedIndex: 1,
                proposedIndex: 3
            ),
            4
        )
        XCTAssertEqual(
            ThumbnailDragMath.dropDestination(
                draggedIndex: 3,
                proposedIndex: 1
            ),
            1
        )
        XCTAssertEqual(
            ThumbnailDragMath.dropDestination(
                draggedIndex: 2,
                proposedIndex: 2
            ),
            2
        )
    }

    func testDropDestinationRoundTripsThroughPagePermutation() {
        let moves = [(0, 3), (3, 0), (1, 4), (4, 1), (2, 2)]

        for (draggedIndex, proposedIndex) in moves {
            let destination = ThumbnailDragMath.dropDestination(
                draggedIndex: draggedIndex,
                proposedIndex: proposedIndex
            )
            let permutation = PageBandAssignment.permutation(
                count: 5,
                moving: IndexSet(integer: draggedIndex),
                to: destination
            )

            XCTAssertEqual(
                permutation[draggedIndex],
                proposedIndex,
                "Failed move from \(draggedIndex) to \(proposedIndex)"
            )
        }
    }
}
