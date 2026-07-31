import CoreGraphics
import Testing
@testable import VellumCore

@Suite("Split grid policy")
struct SplitGridPolicyTests {
    @Test("Axis-neutral fraction math preserves the one-dimensional semantics")
    func axisNeutralFractionMath() {
        #expect(
            SplitLayoutPolicy.maxCount(
                axisLength: 840,
                minLength: 280
            ) == 3
        )
        #expect(
            SplitLayoutPolicy.maxCount(
                axisLength: .nan,
                minLength: 280
            ) == 1
        )

        let lengths = SplitLayoutPolicy.lengths(
            fractions: [1, 3],
            axisLength: 800
        )
        #expect(isApproximatelyEqual(lengths[0], 200))
        #expect(isApproximatelyEqual(lengths[1], 600))

        let clamped = SplitLayoutPolicy.clampedToMinLength(
            fractions: [0.1, 0.4, 0.5],
            axisLength: 1_000,
            minLength: 280
        )
        #expect(clamped.allSatisfy { $0 + 0.0001 >= 0.28 })
        #expect(isApproximatelyEqual(clamped.reduce(0, +), 1))

        let equalFallback = SplitLayoutPolicy.clampedToMinLength(
            fractions: [0.8, 0.1, 0.1],
            axisLength: 700,
            minLength: 280
        )
        #expect(
            equalFallback.allSatisfy {
                isApproximatelyEqual($0, 1 / 3)
            }
        )

        let resized = SplitLayoutPolicy.fractionsResizing(
            [0.4, 0.6],
            dividerIndex: 0,
            byTranslation: 10_000,
            axisLength: 1_000,
            minLength: 280
        )
        #expect(isApproximatelyEqual(resized[0], 0.72))
        #expect(isApproximatelyEqual(resized[1], 0.28))
    }

    @Test("Grid lengths normalize unnormalized column and row shares")
    func gridLengthsNormalizeShares() {
        let grid = SplitGridSnapshot(columns: [
            .init(widthFraction: 1, rowFractions: [1, 3]),
            .init(widthFraction: 3, rowFractions: [2, 2]),
        ])

        let widths = SplitGridPolicy.columnWidths(
            grid: grid,
            containerWidth: 1_000
        )
        let heights = SplitGridPolicy.rowHeights(
            column: grid.columns[0],
            containerHeight: 800
        )

        #expect(isApproximatelyEqual(widths[0], 250))
        #expect(isApproximatelyEqual(widths[1], 750))
        #expect(isApproximatelyEqual(widths.reduce(0, +), 1_000))
        #expect(isApproximatelyEqual(heights[0], 200))
        #expect(isApproximatelyEqual(heights[1], 600))
        #expect(isApproximatelyEqual(heights.reduce(0, +), 800))
        #expect(grid.paneCount == 4)
    }

    @Test("Pane frames tile every column and reject invalid indexes")
    func paneFramesTileTheContainer() throws {
        let grid = SplitGridSnapshot(columns: [
            .init(widthFraction: 1, rowFractions: [1, 1]),
            .init(widthFraction: 3, rowFractions: [1, 2, 1]),
        ])
        let size = CGSize(width: 1_000, height: 800)

        let firstTop = try #require(
            SplitGridPolicy.paneFrame(
                at: PaneIndex(column: 0, row: 0),
                grid: grid,
                containerSize: size
            )
        )
        let firstBottom = try #require(
            SplitGridPolicy.paneFrame(
                at: PaneIndex(column: 0, row: 1),
                grid: grid,
                containerSize: size
            )
        )
        let secondFrames = try (0..<3).map { row in
            try #require(
                SplitGridPolicy.paneFrame(
                    at: PaneIndex(column: 1, row: row),
                    grid: grid,
                    containerSize: size
                )
            )
        }

        #expect(isApproximatelyEqual(firstTop.minX, 0))
        #expect(isApproximatelyEqual(firstTop.width, 250))
        #expect(isApproximatelyEqual(firstTop.height, 400))
        #expect(isApproximatelyEqual(firstBottom.minY, firstTop.maxY))
        #expect(isApproximatelyEqual(firstBottom.maxY, size.height))

        #expect(isApproximatelyEqual(secondFrames[0].minX, 250))
        #expect(isApproximatelyEqual(secondFrames[0].width, 750))
        #expect(isApproximatelyEqual(secondFrames[0].height, 200))
        #expect(isApproximatelyEqual(secondFrames[1].minY, 200))
        #expect(isApproximatelyEqual(secondFrames[1].height, 400))
        #expect(isApproximatelyEqual(secondFrames[2].minY, 600))
        #expect(isApproximatelyEqual(secondFrames[2].maxY, size.height))

        let allFrames = [firstTop, firstBottom] + secondFrames
        let tiledArea = allFrames.reduce(0) {
            $0 + $1.width * $1.height
        }
        #expect(
            isApproximatelyEqual(
                tiledArea,
                size.width * size.height
            )
        )
        #expect(
            SplitGridPolicy.paneFrame(
                at: PaneIndex(column: -1, row: 0),
                grid: grid,
                containerSize: size
            ) == nil
        )
        #expect(
            SplitGridPolicy.paneFrame(
                at: PaneIndex(column: 1, row: 3),
                grid: grid,
                containerSize: size
            ) == nil
        )
    }

    @Test("Horizontal edges win diagonal ties at pane corners")
    func columnBandsTakeCornerPrecedence() {
        let grid = twoByTwoGrid
        let size = CGSize(width: 1_000, height: 800)
        let expected: [(CGPoint, SplitGridDropTarget)] = [
            (CGPoint(x: 0, y: 0), .insertColumn(at: 0)),
            (CGPoint(x: 500, y: 0), .insertColumn(at: 1)),
            (CGPoint(x: 0, y: 400), .insertColumn(at: 0)),
            (CGPoint(x: 500, y: 400), .insertColumn(at: 1)),
        ]

        for (point, target) in expected {
            #expect(
                SplitGridPolicy.dropTarget(
                    at: point,
                    grid: grid,
                    containerSize: size
                ) == target
            )
        }
    }

    @Test("Container edges and column boundaries map to column seams")
    func columnBoundaryTiesMapToSeams() {
        let grid = twoByTwoGrid
        let size = CGSize(width: 1_000, height: 800)
        let expected: [(CGFloat, SplitGridDropTarget)] = [
            (-1, .insertColumn(at: 0)),
            (0, .insertColumn(at: 0)),
            (500, .insertColumn(at: 1)),
            (1_000, .insertColumn(at: 2)),
            (1_001, .insertColumn(at: 2)),
        ]

        for (x, target) in expected {
            #expect(
                SplitGridPolicy.dropTarget(
                    at: CGPoint(x: x, y: 200),
                    grid: grid,
                    containerSize: size
                ) == target
            )
        }
    }

    @Test("Container edges and row boundaries map to row slots")
    func rowBoundaryTiesMapToSlots() {
        let grid = twoByTwoGrid
        let size = CGSize(width: 1_000, height: 800)
        let expected: [(CGFloat, SplitGridDropTarget)] = [
            (-1, .insertRow(column: 0, at: 0)),
            (0, .insertRow(column: 0, at: 0)),
            (400, .insertRow(column: 0, at: 1)),
            (800, .insertRow(column: 0, at: 2)),
            (801, .insertRow(column: 0, at: 2)),
        ]

        for (y, target) in expected {
            #expect(
                SplitGridPolicy.dropTarget(
                    at: CGPoint(x: 250, y: y),
                    grid: grid,
                    containerSize: size
                ) == target
            )
        }

        #expect(
            SplitGridPolicy.dropTarget(
                at: CGPoint(x: 250, y: 200),
                grid: grid,
                containerSize: size
            ) == .insertColumn(at: 0)
        )
    }

    @Test("Normalized wedges stay stable across pane aspect ratios")
    func wedgePartitionIsAspectRatioIndependent() {
        let cases: [(CGSize, [PaneIndex])] = [
            (
                CGSize(width: 800, height: 800),
                [
                    PaneIndex(column: 0, row: 0),
                    PaneIndex(column: 1, row: 0),
                ]
            ),
            (
                CGSize(width: 1_600, height: 800),
                [
                    PaneIndex(column: 0, row: 1),
                    PaneIndex(column: 1, row: 1),
                ]
            ),
        ]

        for (size, panes) in cases {
            let paneWidth = size.width / 2
            let paneHeight = size.height / 2

            for pane in panes {
                let origin = CGPoint(
                    x: CGFloat(pane.column) * paneWidth,
                    y: CGFloat(pane.row) * paneHeight
                )
                let expected: [(CGPoint, SplitGridDropTarget)] = [
                    (
                        CGPoint(
                            x: origin.x + 0.1 * paneWidth,
                            y: origin.y + 0.5 * paneHeight
                        ),
                        .insertColumn(at: pane.column)
                    ),
                    (
                        CGPoint(
                            x: origin.x + 0.9 * paneWidth,
                            y: origin.y + 0.5 * paneHeight
                        ),
                        .insertColumn(at: pane.column + 1)
                    ),
                    (
                        CGPoint(
                            x: origin.x + 0.5 * paneWidth,
                            y: origin.y + 0.1 * paneHeight
                        ),
                        .insertRow(column: pane.column, at: pane.row)
                    ),
                    (
                        CGPoint(
                            x: origin.x + 0.5 * paneWidth,
                            y: origin.y + 0.9 * paneHeight
                        ),
                        .insertRow(column: pane.column, at: pane.row + 1)
                    ),
                ]

                for (point, target) in expected {
                    #expect(
                        SplitGridPolicy.dropTarget(
                            at: point,
                            grid: twoByTwoGrid,
                            containerSize: size
                        ) == target
                    )
                }
            }
        }

        #expect(
            SplitGridPolicy.dropTarget(
                at: CGPoint(x: 200, y: 200),
                grid: twoByTwoGrid,
                containerSize: CGSize(width: 800, height: 800)
            ) == .insertColumn(at: 0)
        )
    }

    @Test("Every interior grid point produces an insertion target")
    func interiorDropTargetsAlwaysInsert() {
        let grid = twoByTwoGrid
        let size = CGSize(width: 1_000, height: 800)

        for x in stride(from: 25, to: 1_000, by: 50) {
            for y in stride(from: 25, to: 800, by: 50) {
                let target = SplitGridPolicy.dropTarget(
                    at: CGPoint(x: x, y: y),
                    grid: grid,
                    containerSize: size
                )

                switch target {
                case let .insertColumn(index):
                    #expect((0...grid.columns.count).contains(index))
                case let .insertRow(column, index):
                    #expect(grid.columns.indices.contains(column))
                    #expect(
                        (0...grid.columns[column].rowFractions.count)
                            .contains(index)
                    )
                case .existingPane:
                    Issue.record("An interior drop must always split a pane.")
                }
            }
        }
    }

    @Test("A held wedge yields only after the hysteresis margin")
    func heldTargetUsesDiagonalHysteresis() {
        let grid = SplitGridSnapshot(columns: [
            .init(widthFraction: 1, rowFractions: [1]),
        ])
        let size = CGSize(width: 1_000, height: 1_000)
        let heldTarget = SplitGridDropTarget.insertColumn(at: 0)

        #expect(
            SplitGridPolicy.dropTarget(
                at: CGPoint(x: 310, y: 300),
                grid: grid,
                containerSize: size,
                holding: heldTarget
            ) == heldTarget
        )
        #expect(
            SplitGridPolicy.dropTarget(
                at: CGPoint(x: 400, y: 300),
                grid: grid,
                containerSize: size,
                holding: heldTarget
            ) == .insertRow(column: 0, at: 0)
        )
    }

    @Test("Feasible targets fall back to the other axis")
    func feasibleDropTargetFallsBackAcrossAxes() {
        let size = CGSize(width: 640, height: 840)
        let columnFullGrid = SplitGridSnapshot(columns: [
            .init(widthFraction: 0.5, rowFractions: [1]),
            .init(widthFraction: 0.5, rowFractions: [1]),
        ])
        let leftWedgePoint = CGPoint(x: 32, y: 252)

        #expect(
            SplitGridPolicy.dropTargets(
                at: leftWedgePoint,
                grid: columnFullGrid,
                containerSize: size
            ) == [
                .insertColumn(at: 0),
                .insertRow(column: 0, at: 0),
            ]
        )
        #expect(
            SplitGridPolicy.feasibleDropTarget(
                at: leftWedgePoint,
                grid: columnFullGrid,
                containerSize: size
            ) == .insertRow(column: 0, at: 0)
        )

        let bothAxesFullGrid = SplitGridSnapshot(columns: [
            .init(widthFraction: 0.5, rowFractions: [1, 1, 1]),
            .init(widthFraction: 0.5, rowFractions: [1, 1, 1]),
        ])
        #expect(
            SplitGridPolicy.feasibleDropTarget(
                at: CGPoint(x: 32, y: 84),
                grid: bothAxesFullGrid,
                containerSize: size
            ) == nil
        )
    }

    @Test("Preview insertion uses the commit share primitive on both axes")
    func previewInsertionUsesCommitFractionMath() throws {
        let grid = SplitGridSnapshot(columns: [
            .init(widthFraction: 1, rowFractions: [1, 3]),
            .init(widthFraction: 3, rowFractions: [2, 1]),
        ])
        let expectedWidths = SplitLayoutPolicy.fractionsInserting(
            at: 1,
            into: grid.columns.map(\.widthFraction)
        )
        let columnResult = try #require(
            SplitGridPolicy.gridInserting(
                .insertColumn(at: 1),
                into: grid
            )
        )

        #expect(columnResult.columns.map(\.widthFraction) == expectedWidths)
        #expect(columnResult.columns[1].rowFractions == [1])
        #expect(columnResult.columns[0].rowFractions == [1, 3])
        #expect(columnResult.columns[2].rowFractions == [2, 1])

        let expectedRows = SplitLayoutPolicy.fractionsInserting(
            at: 1,
            into: grid.columns[1].rowFractions
        )
        let rowResult = try #require(
            SplitGridPolicy.gridInserting(
                .insertRow(column: 1, at: 1),
                into: grid
            )
        )

        #expect(rowResult.columns.map(\.widthFraction) == [1, 3])
        #expect(rowResult.columns[1].rowFractions == expectedRows)
        #expect(rowResult.columns[0].rowFractions == [1, 3])
        #expect(
            SplitGridPolicy.gridInserting(
                .existingPane(PaneIndex(column: 0, row: 0)),
                into: grid
            ) == nil
        )
        #expect(
            SplitGridPolicy.gridInserting(
                .insertRow(column: 2, at: 0),
                into: grid
            ) == nil
        )
    }

    @Test("Pane indexes follow preview insertions without changing identity")
    func paneIndexesTrackPreviewInsertions() {
        #expect(
            SplitGridPolicy.paneIndexAfterInserting(
                .insertColumn(at: 1),
                PaneIndex(column: 0, row: 1)
            ) == PaneIndex(column: 0, row: 1)
        )
        #expect(
            SplitGridPolicy.paneIndexAfterInserting(
                .insertColumn(at: 1),
                PaneIndex(column: 1, row: 1)
            ) == PaneIndex(column: 2, row: 1)
        )
        #expect(
            SplitGridPolicy.paneIndexAfterInserting(
                .insertRow(column: 0, at: 1),
                PaneIndex(column: 0, row: 1)
            ) == PaneIndex(column: 0, row: 2)
        )
        #expect(
            SplitGridPolicy.paneIndexAfterInserting(
                .insertRow(column: 0, at: 1),
                PaneIndex(column: 1, row: 1)
            ) == PaneIndex(column: 1, row: 1)
        )
        #expect(
            SplitGridPolicy.insertedPaneIndex(
                for: .insertColumn(at: 1)
            ) == PaneIndex(column: 1, row: 0)
        )
        #expect(
            SplitGridPolicy.insertedPaneIndex(
                for: .insertRow(column: 1, at: 2)
            ) == PaneIndex(column: 1, row: 2)
        )
        #expect(
            SplitGridPolicy.insertedPaneIndex(
                for: .existingPane(PaneIndex(column: 0, row: 0))
            ) == nil
        )
    }

    @Test("Allows applies capacity independently on each axis")
    func allowsUsesPerAxisCapacity() {
        let grid = SplitGridSnapshot(columns: [
            .init(widthFraction: 0.5, rowFractions: [1, 1, 1]),
            .init(widthFraction: 0.5, rowFractions: [1, 1]),
        ])
        let size = CGSize(width: 640, height: 840)

        #expect(
            !SplitGridPolicy.allows(
                .insertColumn(at: 1),
                grid: grid,
                containerSize: size
            )
        )
        #expect(
            !SplitGridPolicy.allows(
                .insertRow(column: 0, at: 3),
                grid: grid,
                containerSize: size
            )
        )
        #expect(
            SplitGridPolicy.allows(
                .insertRow(column: 1, at: 2),
                grid: grid,
                containerSize: size
            )
        )
        #expect(
            SplitGridPolicy.allows(
                .existingPane(PaneIndex(column: 1, row: 1)),
                grid: grid,
                containerSize: size
            )
        )
        #expect(
            !SplitGridPolicy.allows(
                .insertColumn(at: 3),
                grid: grid,
                containerSize: size
            )
        )
        #expect(
            !SplitGridPolicy.allows(
                .insertRow(column: 2, at: 0),
                grid: grid,
                containerSize: size
            )
        )
        #expect(
            !SplitGridPolicy.allows(
                .existingPane(PaneIndex(column: 0, row: 3)),
                grid: grid,
                containerSize: size
            )
        )
    }

    @Test("Column divider resizing clamps at 320 points")
    func columnDividerResizingClampsAtMinimum() {
        let grid = twoByTwoGrid
        let resized = SplitGridPolicy.resizingColumnDivider(
            grid,
            dividerIndex: 0,
            byTranslation: 10_000,
            containerWidth: 1_000
        )

        #expect(
            isApproximatelyEqual(
                resized.columns[0].widthFraction,
                0.68
            )
        )
        #expect(
            isApproximatelyEqual(
                resized.columns[1].widthFraction,
                0.32
            )
        )
        #expect(
            SplitGridPolicy.resizingColumnDivider(
                grid,
                dividerIndex: 1,
                byTranslation: 100,
                containerWidth: 1_000
            ) == grid
        )
    }

    @Test("Row divider resizing clamps at 280 points")
    func rowDividerResizingClampsAtMinimum() {
        let grid = twoByTwoGrid
        let resized = SplitGridPolicy.resizingRowDivider(
            grid,
            column: 1,
            dividerIndex: 0,
            byTranslation: -10_000,
            containerHeight: 1_000
        )

        #expect(
            isApproximatelyEqual(
                resized.columns[1].rowFractions[0],
                0.28
            )
        )
        #expect(
            isApproximatelyEqual(
                resized.columns[1].rowFractions[1],
                0.72
            )
        )
        #expect(
            SplitGridPolicy.resizingRowDivider(
                grid,
                column: -1,
                dividerIndex: 0,
                byTranslation: 100,
                containerHeight: 1_000
            ) == grid
        )
        #expect(
            SplitGridPolicy.resizingRowDivider(
                grid,
                column: 0,
                dividerIndex: 1,
                byTranslation: 100,
                containerHeight: 1_000
            ) == grid
        )
    }

    @Test("Reclamping removes height overflow before width overflow")
    func reclampUsesNormativeOverflowOrder() {
        let grid = SplitGridSnapshot(columns: [
            .init(widthFraction: 1, rowFractions: [1, 1, 1, 1]),
            .init(widthFraction: 2, rowFractions: [1, 1, 1]),
            .init(widthFraction: 3, rowFractions: [1, 1, 1, 1]),
            .init(widthFraction: 4, rowFractions: [1, 1]),
        ])

        let result = SplitGridPolicy.reclamped(
            grid,
            containerSize: CGSize(width: 640, height: 560)
        )

        #expect(result.overflow == [
            PaneIndex(column: 0, row: 3),
            PaneIndex(column: 0, row: 2),
            PaneIndex(column: 1, row: 2),
            PaneIndex(column: 2, row: 3),
            PaneIndex(column: 2, row: 2),
            PaneIndex(column: 3, row: 1),
            PaneIndex(column: 3, row: 0),
            PaneIndex(column: 2, row: 1),
            PaneIndex(column: 2, row: 0),
        ])
        #expect(result.grid.columns.count == 2)
        #expect(
            result.grid.columns.allSatisfy {
                $0.rowFractions.count == 2
            }
        )
        #expect(
            result.grid.columns.allSatisfy {
                isApproximatelyEqual($0.widthFraction, 0.5)
            }
        )
        #expect(
            result.grid.columns.flatMap(\.rowFractions).allSatisfy {
                isApproximatelyEqual($0, 0.5)
            }
        )
    }

    @Test("Reclamping trims tall columns and removes empty columns")
    func reclampNeverReturnsEmptyColumns() {
        let grid = SplitGridSnapshot(columns: [
            .init(widthFraction: 1, rowFractions: [1, 1, 1]),
            .init(widthFraction: 5, rowFractions: []),
            .init(widthFraction: 2, rowFractions: [1]),
        ])

        let result = SplitGridPolicy.reclamped(
            grid,
            containerSize: CGSize(width: 640, height: 560)
        )

        #expect(
            result.overflow == [PaneIndex(column: 0, row: 2)]
        )
        #expect(result.grid.columns.count == 2)
        #expect(
            result.grid.columns.allSatisfy {
                !$0.rowFractions.isEmpty
            }
        )
        #expect(result.grid.paneCount == 3)
    }

    @Test("Reclamping enforces minimum fractions and infeasible equal shares")
    func reclampClampsFractions() {
        let grid = SplitGridSnapshot(columns: [
            .init(widthFraction: 0.1, rowFractions: [0.1, 0.4, 0.5]),
            .init(widthFraction: 0.4, rowFractions: [1]),
            .init(widthFraction: 0.5, rowFractions: [1]),
        ])

        let clamped = SplitGridPolicy.reclamped(
            grid,
            containerSize: CGSize(width: 1_000, height: 1_000)
        )

        #expect(
            clamped.grid.columns.allSatisfy {
                $0.widthFraction + 0.0001 >= 0.32
            }
        )
        #expect(
            clamped.grid.columns[0].rowFractions.allSatisfy {
                $0 + 0.0001 >= 0.28
            }
        )
        #expect(
            isApproximatelyEqual(
                clamped.grid.columns.map(\.widthFraction).reduce(0, +),
                1
            )
        )
        #expect(
            isApproximatelyEqual(
                clamped.grid.columns[0].rowFractions.reduce(0, +),
                1
            )
        )

        let infeasible = SplitGridPolicy.reclamped(
            grid,
            containerSize: CGSize(width: 100, height: 100)
        )
        #expect(infeasible.grid.columns.count == 1)
        #expect(
            infeasible.grid.columns[0].rowFractions.count == 1
        )
        #expect(
            isApproximatelyEqual(
                infeasible.grid.columns[0].widthFraction,
                1
            )
        )
        #expect(
            isApproximatelyEqual(
                infeasible.grid.columns[0].rowFractions[0],
                1
            )
        )
    }

    @Test("Empty grids NaN points and zero containers stay deterministic")
    func degenerateInputsAreDeterministic() throws {
        let empty = SplitGridSnapshot(columns: [])
        #expect(
            SplitGridPolicy.dropTarget(
                at: CGPoint(x: 10, y: 10),
                grid: empty,
                containerSize: CGSize(width: 1_000, height: 800)
            ) == .insertColumn(at: 0)
        )
        #expect(
            SplitGridPolicy.dropTarget(
                at: CGPoint(x: CGFloat.nan, y: 10),
                grid: twoByTwoGrid,
                containerSize: CGSize(width: 1_000, height: 800)
            ) == .insertColumn(at: 0)
        )
        #expect(
            SplitGridPolicy.dropTarget(
                at: CGPoint(x: 10, y: CGFloat.nan),
                grid: twoByTwoGrid,
                containerSize: CGSize(width: 1_000, height: 800)
            ) == .insertColumn(at: 0)
        )
        #expect(
            SplitGridPolicy.reclamped(
                empty,
                containerSize: .zero
            ) == .init(grid: empty, overflow: [])
        )

        let unnormalized = SplitGridSnapshot(columns: [
            .init(widthFraction: 3, rowFractions: [3, 1]),
            .init(widthFraction: 1, rowFractions: [0, 0]),
        ])
        let reclamped = SplitGridPolicy.reclamped(
            unnormalized,
            containerSize: .zero
        )
        #expect(reclamped.overflow.isEmpty)
        #expect(
            isApproximatelyEqual(
                reclamped.grid.columns[0].widthFraction,
                0.75
            )
        )
        #expect(
            isApproximatelyEqual(
                reclamped.grid.columns[1].widthFraction,
                0.25
            )
        )
        #expect(
            isApproximatelyEqual(
                reclamped.grid.columns[0].rowFractions[0],
                0.75
            )
        )
        #expect(
            reclamped.grid.columns[1].rowFractions.allSatisfy {
                isApproximatelyEqual($0, 0.5)
            }
        )

        let zeroFrame = try #require(
            SplitGridPolicy.paneFrame(
                at: PaneIndex(column: 0, row: 0),
                grid: unnormalized,
                containerSize: .zero
            )
        )
        #expect(zeroFrame == .zero)
    }

    private var twoByTwoGrid: SplitGridSnapshot {
        SplitGridSnapshot(columns: [
            .init(widthFraction: 0.5, rowFractions: [0.5, 0.5]),
            .init(widthFraction: 0.5, rowFractions: [0.5, 0.5]),
        ])
    }

    private func isApproximatelyEqual(
        _ first: CGFloat,
        _ second: CGFloat,
        tolerance: CGFloat = 0.0001
    ) -> Bool {
        abs(first - second) <= tolerance
    }
}
