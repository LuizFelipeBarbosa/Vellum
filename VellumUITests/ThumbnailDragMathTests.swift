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

    func testDisplacementShiftsOnlyTheRowsTheDraggedRowPassesOver() {
        // Rows 0..<5 at a 100pt row height: only the rows between the dragged row and its
        // proposed slot move, and they move one row's worth against the drag.
        let cases: [(dragged: Int, proposed: Int, expected: [CGFloat], line: UInt)] = [
            (1, 3, [0, 0, -100, -100, 0], #line), // dragging down
            (3, 1, [0, 100, 100, 0, 0], #line), // dragging up
            (2, 2, [0, 0, 0, 0, 0], #line), // proposed index unchanged
        ]

        for (dragged, proposed, expected, line) in cases {
            let displacements = (0..<5).map {
                ThumbnailDragMath.displacement(
                    forRow: $0,
                    draggedIndex: dragged,
                    proposedIndex: proposed,
                    rowHeight: 100
                )
            }

            XCTAssertEqual(displacements, expected, line: line)
        }
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

    func testDragStartIndexAcceptsRowInteriorsAndRejectsBadgeAndVirtualRows() {
        // A 214x100 row over 4 pages, with a 44pt delete-badge zone in each row's
        // top-right corner: rows span y 0..<400 and the badge zone of row 1 is
        // x 170..<214, y 100..<144.
        let cases: [(x: CGFloat, y: CGFloat, expected: Int?, reason: String, line: UInt)] = [
            (107, 250, 2, "the middle of row 2", #line),
            (171, 110, nil, "inside row 1's delete badge zone", #line),
            (169, 110, 1, "one point left of the delete badge zone", #line),
            (171, 145, 1, "one point below the delete badge zone", #line),
            (107, 400, nil, "the virtual row past the last page", #line),
            (107, -1, nil, "above the top of the first row", #line),
        ]

        for (x, y, expected, reason, line) in cases {
            XCTAssertEqual(
                ThumbnailDragMath.dragStartIndex(
                    fingerContentX: x,
                    fingerContentY: y,
                    rowWidth: 214,
                    rowHeight: 100,
                    badgeZone: 44,
                    pageCount: 4
                ),
                expected,
                reason,
                line: line
            )
        }
    }
}
