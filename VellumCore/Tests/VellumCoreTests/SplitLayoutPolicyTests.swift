import CoreGraphics
import Testing
@testable import VellumCore

@Suite("Split layout policy")
struct SplitLayoutPolicyTests {
    @Test("Normalization handles empty, zero, negative, and normalized shares")
    func normalizationHandlesSupportedInputs() {
        #expect(SplitLayoutPolicy.normalized([]).isEmpty)

        let equalShares = SplitLayoutPolicy.normalized([0, 0, 0])
        #expect(equalShares.allSatisfy { isApproximatelyEqual($0, 1 / 3) })
        #expect(isApproximatelyEqual(equalShares.reduce(0, +), 1))

        let clampedNegatives = SplitLayoutPolicy.normalized([-2, 1, 2])
        #expect(isApproximatelyEqual(clampedNegatives[0], 0))
        #expect(isApproximatelyEqual(clampedNegatives[1], 1 / 3))
        #expect(isApproximatelyEqual(clampedNegatives[2], 2 / 3))
        #expect(isApproximatelyEqual(clampedNegatives.reduce(0, +), 1))

        let alreadyNormalized: [CGFloat] = [0.2, 0.3, 0.5]
        let roundTrip = SplitLayoutPolicy.normalized(alreadyNormalized)
        for (actual, expected) in zip(roundTrip, alreadyNormalized) {
            #expect(isApproximatelyEqual(actual, expected))
        }
        #expect(isApproximatelyEqual(roundTrip.reduce(0, +), 1))
    }

    @Test("Pane widths resolve normalized and unnormalized shares")
    func paneWidthsSumToContainerWidth() {
        let cases: [([CGFloat], CGFloat)] = [
            ([0.25, 0.75], 800),
            ([1, 1, 2], 1_024),
            ([3, 2, 1, 4], 1_366),
        ]

        for (fractions, containerWidth) in cases {
            let widths = SplitLayoutPolicy.paneWidths(
                fractions: fractions,
                containerWidth: containerWidth
            )
            #expect(isApproximatelyEqual(widths.reduce(0, +), containerWidth))
        }
    }

    @Test("Divider resizing changes only its two neighboring panes")
    func dividerResizingChangesOnlyNeighbors() {
        let start: [CGFloat] = [0.1, 0.35, 0.35, 0.2]
        let result = SplitLayoutPolicy.fractionsResizing(
            start,
            dividerIndex: 1,
            byTranslation: 100,
            containerWidth: 2_000
        )

        #expect(result[0] == start[0])
        #expect(result[3] == start[3])
        #expect(isApproximatelyEqual(result[1], 0.4))
        #expect(isApproximatelyEqual(result[2], 0.3))
        #expect(isApproximatelyEqual(result.reduce(0, +), 1))
    }

    @Test("Divider resizing clamps both directions at the minimum width")
    func dividerResizingClampsAtMinimumWidth() {
        let start: [CGFloat] = [0.4, 0.6]
        let movedRight = SplitLayoutPolicy.fractionsResizing(
            start,
            dividerIndex: 0,
            byTranslation: 10_000,
            containerWidth: 1_000
        )
        let movedLeft = SplitLayoutPolicy.fractionsResizing(
            start,
            dividerIndex: 0,
            byTranslation: -10_000,
            containerWidth: 1_000
        )

        #expect(isApproximatelyEqual(movedRight[0], 0.68))
        #expect(isApproximatelyEqual(movedRight[1], 0.32))
        #expect(isApproximatelyEqual(movedLeft[0], 0.32))
        #expect(isApproximatelyEqual(movedLeft[1], 0.68))
        #expect(isApproximatelyEqual(movedRight.reduce(0, +), 1))
        #expect(isApproximatelyEqual(movedLeft.reduce(0, +), 1))
    }

    @Test("Invalid dividers and undersized arrays leave fractions exactly unchanged")
    func invalidDividerResizingIsANoOp() {
        let start: [CGFloat] = [0.2, 0.3, 0.5]

        #expect(
            SplitLayoutPolicy.fractionsResizing(
                start,
                dividerIndex: -1,
                byTranslation: 100,
                containerWidth: 1_500
            ) == start
        )
        #expect(
            SplitLayoutPolicy.fractionsResizing(
                start,
                dividerIndex: 2,
                byTranslation: 100,
                containerWidth: 1_500
            ) == start
        )

        let singlePane: [CGFloat] = [1]
        #expect(
            SplitLayoutPolicy.fractionsResizing(
                singlePane,
                dividerIndex: 0,
                byTranslation: 100,
                containerWidth: 1_500
            ) == singlePane
        )
    }

    @Test("Insertion reserves an equal-count share for the new pane")
    func insertionReservesEqualCountShare() {
        let insertedIntoOne = SplitLayoutPolicy.fractionsInserting(
            at: 1,
            into: [1]
        )
        #expect(insertedIntoOne.allSatisfy { isApproximatelyEqual($0, 0.5) })

        let insertedIntoTwo = SplitLayoutPolicy.fractionsInserting(
            at: 1,
            into: [0.5, 0.5]
        )
        #expect(insertedIntoTwo.count == 3)
        #expect(insertedIntoTwo.allSatisfy { isApproximatelyEqual($0, 1 / 3) })
        #expect(isApproximatelyEqual(insertedIntoTwo.reduce(0, +), 1))

        #expect(SplitLayoutPolicy.fractionsInserting(at: 7, into: []) == [1])
    }

    @Test("Insertion clamps indices to the nearest valid slot")
    func insertionClampsIndices() {
        let insertedBefore = SplitLayoutPolicy.fractionsInserting(
            at: -4,
            into: [0.25, 0.75]
        )
        let insertedAfter = SplitLayoutPolicy.fractionsInserting(
            at: 8,
            into: [0.25, 0.75]
        )
        let expectedBefore: [CGFloat] = [1 / 3, 1 / 6, 1 / 2]
        let expectedAfter: [CGFloat] = [1 / 6, 1 / 2, 1 / 3]

        for (actual, expected) in zip(insertedBefore, expectedBefore) {
            #expect(isApproximatelyEqual(actual, expected))
        }
        for (actual, expected) in zip(insertedAfter, expectedAfter) {
            #expect(isApproximatelyEqual(actual, expected))
        }
    }

    @Test("Removal proportionally redistributes the removed share")
    func removalRedistributesProportionally() {
        let twoPaneResult = SplitLayoutPolicy.fractionsRemoving(
            at: 0,
            from: [0.25, 0.75]
        )
        #expect(twoPaneResult.count == 1)
        #expect(isApproximatelyEqual(twoPaneResult[0], 1))

        let proportionalResult = SplitLayoutPolicy.fractionsRemoving(
            at: 1,
            from: [0.2, 0.3, 0.5]
        )
        #expect(isApproximatelyEqual(proportionalResult[0], 2 / 7))
        #expect(isApproximatelyEqual(proportionalResult[1], 5 / 7))
        #expect(isApproximatelyEqual(proportionalResult.reduce(0, +), 1))

        #expect(SplitLayoutPolicy.fractionsRemoving(at: 0, from: [1]).isEmpty)
    }

    @Test("Removal splits equally when surviving shares are all zero")
    func removalSplitsZeroSurvivorsEqually() {
        let result = SplitLayoutPolicy.fractionsRemoving(
            at: 0,
            from: [1, 0, 0]
        )

        #expect(result.allSatisfy { isApproximatelyEqual($0, 0.5) })
    }

    @Test("Invalid removals leave fractions exactly unchanged")
    func invalidRemovalIsANoOp() {
        let fractions: [CGFloat] = [0.2, 0.3, 0.5]

        #expect(
            SplitLayoutPolicy.fractionsRemoving(at: -1, from: fractions)
                == fractions
        )
        #expect(
            SplitLayoutPolicy.fractionsRemoving(at: 3, from: fractions)
                == fractions
        )
        #expect(SplitLayoutPolicy.fractionsRemoving(at: 0, from: []).isEmpty)
    }

    @Test("Drop targeting maps exact boundaries and edge thresholds to insertion")
    func dropTargetBoundariesFavorInsertion() {
        let fractions: [CGFloat] = [0.5, 0.5]

        #expect(
            SplitLayoutPolicy.dropTarget(
                forX: 0,
                fractions: fractions,
                containerWidth: 1_000
            ) == .insertBetween(index: 0)
        )
        #expect(
            SplitLayoutPolicy.dropTarget(
                forX: 125,
                fractions: fractions,
                containerWidth: 1_000
            ) == .insertBetween(index: 0)
        )
        #expect(
            SplitLayoutPolicy.dropTarget(
                forX: 375,
                fractions: fractions,
                containerWidth: 1_000
            ) == .insertBetween(index: 1)
        )
        #expect(
            SplitLayoutPolicy.dropTarget(
                forX: 500,
                fractions: fractions,
                containerWidth: 1_000
            ) == .insertBetween(index: 1)
        )
        #expect(
            SplitLayoutPolicy.dropTarget(
                forX: 625,
                fractions: fractions,
                containerWidth: 1_000
            ) == .insertBetween(index: 1)
        )
        #expect(
            SplitLayoutPolicy.dropTarget(
                forX: 875,
                fractions: fractions,
                containerWidth: 1_000
            ) == .insertBetween(index: 2)
        )
        #expect(
            SplitLayoutPolicy.dropTarget(
                forX: 1_000,
                fractions: fractions,
                containerWidth: 1_000
            ) == .insertBetween(index: 2)
        )
    }

    @Test("Drop targeting distinguishes pane edge zones from interiors")
    func dropTargetDistinguishesEdgesAndInteriors() {
        let fractions: [CGFloat] = [0.5, 0.5]
        let expectedTargets: [(CGFloat, SplitDropTarget)] = [
            (50, .insertBetween(index: 0)),
            (250, .existingPane(index: 0)),
            (450, .insertBetween(index: 1)),
            (550, .insertBetween(index: 1)),
            (750, .existingPane(index: 1)),
            (950, .insertBetween(index: 2)),
        ]

        for (x, expected) in expectedTargets {
            #expect(
                SplitLayoutPolicy.dropTarget(
                    forX: x,
                    fractions: fractions,
                    containerWidth: 1_000
                ) == expected
            )
        }
    }

    @Test("Drop targeting handles coordinates outside the container")
    func dropTargetHandlesOutsideCoordinates() {
        let fractions: [CGFloat] = [0.5, 0.5]

        #expect(
            SplitLayoutPolicy.dropTarget(
                forX: -1,
                fractions: fractions,
                containerWidth: 1_000
            ) == .insertBetween(index: 0)
        )
        #expect(
            SplitLayoutPolicy.dropTarget(
                forX: 1_001,
                fractions: fractions,
                containerWidth: 1_000
            ) == .insertBetween(index: 2)
        )
        #expect(
            SplitLayoutPolicy.dropTarget(
                forX: 200,
                fractions: [],
                containerWidth: 1_000
            ) == .insertBetween(index: 0)
        )
    }

    @Test("A single pane uses edge zones around its interior")
    func singlePaneDropTargetUsesEdgeZones() {
        let expectedTargets: [(CGFloat, SplitDropTarget)] = [
            (50, .insertBetween(index: 0)),
            (200, .existingPane(index: 0)),
            (350, .insertBetween(index: 1)),
        ]

        for (x, expected) in expectedTargets {
            #expect(
                SplitLayoutPolicy.dropTarget(
                    forX: x,
                    fractions: [1],
                    containerWidth: 400
                ) == expected
            )
        }
    }

    @Test("Maximum pane count follows the minimum pane width")
    func maximumPaneCountUsesMinimumWidth() {
        #expect(SplitLayoutPolicy.maxPaneCount(forContainerWidth: 834) == 2)
        #expect(SplitLayoutPolicy.maxPaneCount(forContainerWidth: 1_194) == 3)
        #expect(SplitLayoutPolicy.maxPaneCount(forContainerWidth: 1_366) == 4)
        #expect(SplitLayoutPolicy.maxPaneCount(forContainerWidth: 100) == 1)
        #expect(SplitLayoutPolicy.maxPaneCount(forContainerWidth: 0) == 1)
        #expect(SplitLayoutPolicy.maxPaneCount(forContainerWidth: -100) == 1)
    }

    @Test("Minimum clamping falls back to equal shares when the container is too small")
    func minimumClampingFallsBackWhenInfeasible() {
        let result = SplitLayoutPolicy.clampedToMinWidth(
            fractions: [0.8, 0.1, 0.1],
            containerWidth: 900
        )

        #expect(result.allSatisfy { isApproximatelyEqual($0, 1 / 3) })
        #expect(isApproximatelyEqual(result.reduce(0, +), 1))
    }

    @Test("Minimum clamping takes deficits proportionally from wider panes")
    func minimumClampingRedistributesDeficit() {
        let result = SplitLayoutPolicy.clampedToMinWidth(
            fractions: [0.2, 0.4, 0.4],
            containerWidth: 1_000
        )

        #expect(isApproximatelyEqual(result[0], 0.32))
        #expect(isApproximatelyEqual(result[1], 0.34))
        #expect(isApproximatelyEqual(result[2], 0.34))
        #expect(isApproximatelyEqual(result.reduce(0, +), 1))
    }

    private func isApproximatelyEqual(
        _ first: CGFloat,
        _ second: CGFloat,
        tolerance: CGFloat = 0.0001
    ) -> Bool {
        abs(first - second) <= tolerance
    }
}
