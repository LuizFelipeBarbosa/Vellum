import CoreGraphics
import Foundation

public struct PaneIndex: Hashable, Sendable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

public struct SplitGridSnapshot: Equatable, Sendable {
    public struct Column: Equatable, Sendable {
        public var widthFraction: CGFloat
        public var rowFractions: [CGFloat]

        public init(widthFraction: CGFloat, rowFractions: [CGFloat]) {
            self.widthFraction = widthFraction
            self.rowFractions = rowFractions
        }
    }

    public var columns: [Column]

    public init(columns: [Column]) {
        self.columns = columns
    }

    public var paneCount: Int {
        columns.reduce(0) { $0 + $1.rowFractions.count }
    }
}

public enum SplitGridDropTarget: Equatable, Sendable {
    case insertColumn(at: Int)
    case insertRow(column: Int, at: Int)
    /// `dropTarget` and `dropTargets` never produce this non-destructive target.
    case existingPane(PaneIndex)
}

public enum SplitGridPolicy {
    public static let minPaneWidth: CGFloat = 320
    public static let minPaneHeight: CGFloat = 280
    /// Wedge boundaries are diagonals; a finger tracking along one would otherwise
    /// flip the preview every frame. A challenger must clear the held wedge by this margin.
    public static let dropHysteresisFraction: CGFloat = 0.04
    public static let dividerHitThickness: CGFloat = 24

    /// The horizontal limit keeps every feasible column wide enough to use.
    public static func maxColumnCount(
        forContainerWidth width: CGFloat
    ) -> Int {
        SplitLayoutPolicy.maxCount(
            axisLength: width,
            minLength: minPaneWidth
        )
    }

    /// The vertical limit keeps every feasible row tall enough to use.
    public static func maxRowCount(
        forContainerHeight height: CGFloat
    ) -> Int {
        SplitLayoutPolicy.maxCount(
            axisLength: height,
            minLength: minPaneHeight
        )
    }

    /// Normalizing column shares on read keeps stored snapshots independent of container width.
    public static func columnWidths(
        grid: SplitGridSnapshot,
        containerWidth: CGFloat
    ) -> [CGFloat] {
        SplitLayoutPolicy.lengths(
            fractions: grid.columns.map(\.widthFraction),
            axisLength: containerWidth
        )
    }

    /// Normalizing row shares on read keeps stored columns independent of container height.
    public static func rowHeights(
        column: SplitGridSnapshot.Column,
        containerHeight: CGFloat
    ) -> [CGFloat] {
        SplitLayoutPolicy.lengths(
            fractions: column.rowFractions,
            axisLength: containerHeight
        )
    }

    /// Prefix sums make each pane tile its column without storing container-specific frames.
    public static func paneFrame(
        at index: PaneIndex,
        grid: SplitGridSnapshot,
        containerSize: CGSize
    ) -> CGRect? {
        guard grid.columns.indices.contains(index.column) else { return nil }

        let column = grid.columns[index.column]
        guard column.rowFractions.indices.contains(index.row) else {
            return nil
        }

        let widths = columnWidths(
            grid: grid,
            containerWidth: containerSize.width
        )
        let heights = rowHeights(
            column: column,
            containerHeight: containerSize.height
        )
        let x = widths[..<index.column].reduce(0, +)
        let y = heights[..<index.row].reduce(0, +)
        return CGRect(
            x: x,
            y: y,
            width: widths[index.column],
            height: heights[index.row]
        )
    }

    /// The nearest pane edge wins. The other axis's nearest edge follows it, so a full
    /// axis does not turn half of a pane into a refusal.
    public static func dropTargets(
        at point: CGPoint,
        grid: SplitGridSnapshot,
        containerSize: CGSize,
        holding heldTarget: SplitGridDropTarget? = nil
    ) -> [SplitGridDropTarget] {
        guard !grid.columns.isEmpty,
              !point.x.isNaN,
              !point.y.isNaN else {
            return [.insertColumn(at: 0)]
        }

        let width = usableLength(containerSize.width)
        guard width > 0 else { return [.insertColumn(at: 0)] }

        // The drag point comes from a long press that keeps reporting the finger
        // outside the container, so the safe-area bands are ordinary drop points.
        // Clamping resolves them through the tiling loop; returning early there
        // would drop the cross-axis fallback exactly where a full axis needs it.
        let x = min(max(point.x, 0), width)
        let widths = columnWidths(grid: grid, containerWidth: width)
        var columnStartX: CGFloat = 0

        for (columnIndex, columnWidth) in widths.enumerated() {
            let columnEndX = columnStartX + columnWidth
            // The last column absorbs the trailing edge: rounding in the share
            // math can leave the tiled widths a hair short of the container.
            guard x <= columnEndX || columnIndex == widths.count - 1 else {
                columnStartX = columnEndX
                continue
            }

            return dropTargetsInsideColumn(
                atY: point.y,
                localX: min(x - columnStartX, columnWidth),
                columnIndex: columnIndex,
                columnWidth: columnWidth,
                column: grid.columns[columnIndex],
                containerHeight: containerSize.height,
                holding: heldTarget
            )
        }

        return [.insertColumn(at: grid.columns.count)]
    }

    /// Returns the first target in the edge ranking.
    public static func dropTarget(
        at point: CGPoint,
        grid: SplitGridSnapshot,
        containerSize: CGSize,
        holding heldTarget: SplitGridDropTarget? = nil
    ) -> SplitGridDropTarget {
        return dropTargets(
            at: point,
            grid: grid,
            containerSize: containerSize,
            holding: heldTarget
        ).first!
    }

    /// Returns nil when neither axis can accept another pane at this point.
    public static func feasibleDropTarget(
        at point: CGPoint,
        grid: SplitGridSnapshot,
        containerSize: CGSize,
        holding heldTarget: SplitGridDropTarget? = nil
    ) -> SplitGridDropTarget? {
        dropTargets(
            at: point,
            grid: grid,
            containerSize: containerSize,
            holding: heldTarget
        ).first {
            allows($0, grid: grid, containerSize: containerSize)
        }
    }

    /// The preview uses the commit path's share primitive, so its geometry cannot
    /// jump when the drop is committed.
    public static func gridInserting(
        _ target: SplitGridDropTarget,
        into grid: SplitGridSnapshot
    ) -> SplitGridSnapshot? {
        // Matching NoteSplitState's clamping and fractionsInserting calls exactly
        // keeps the preview's shares identical to insertColumn/stackPane on commit.
        switch target {
        case let .insertColumn(index):
            let insertionIndex = min(max(index, 0), grid.columns.count)
            let widths = SplitLayoutPolicy.fractionsInserting(
                at: insertionIndex,
                into: grid.columns.map(\.widthFraction)
            )
            var columns = grid.columns
            columns.insert(
                .init(
                    widthFraction: widths[insertionIndex],
                    rowFractions: [1]
                ),
                at: insertionIndex
            )
            for columnIndex in columns.indices {
                columns[columnIndex].widthFraction = widths[columnIndex]
            }
            return SplitGridSnapshot(columns: columns)

        case let .insertRow(columnIndex, rowIndex):
            guard grid.columns.indices.contains(columnIndex) else {
                return nil
            }
            let rows = grid.columns[columnIndex].rowFractions
            let insertionIndex = min(max(rowIndex, 0), rows.count)
            var result = grid
            result.columns[columnIndex].rowFractions =
                SplitLayoutPolicy.fractionsInserting(
                    at: insertionIndex,
                    into: rows
                )
            return result

        case .existingPane:
            return nil
        }
    }

    /// Existing panes retain identity while their affected index moves past an insertion.
    public static func paneIndexAfterInserting(
        _ target: SplitGridDropTarget,
        _ index: PaneIndex
    ) -> PaneIndex {
        switch target {
        case let .insertColumn(insertionIndex):
            guard index.column >= insertionIndex else { return index }
            return PaneIndex(column: index.column + 1, row: index.row)

        case let .insertRow(columnIndex, insertionIndex):
            guard index.column == columnIndex,
                  index.row >= insertionIndex else {
                return index
            }
            return PaneIndex(column: index.column, row: index.row + 1)

        case .existingPane:
            return index
        }
    }

    /// Returns the new pane's index so the preview can frame its ghost.
    public static func insertedPaneIndex(
        for target: SplitGridDropTarget
    ) -> PaneIndex? {
        switch target {
        case let .insertColumn(index):
            return PaneIndex(column: index, row: 0)
        case let .insertRow(columnIndex, rowIndex):
            return PaneIndex(column: columnIndex, row: rowIndex)
        case .existingPane:
            return nil
        }
    }

    /// A refused insertion owns no pane, so callers that must draw it use the
    /// nearest existing pane instead of a hypothetical grid's coordinates.
    public static func clampedPaneIndex(
        for target: SplitGridDropTarget,
        in grid: SplitGridSnapshot
    ) -> PaneIndex? {
        let index: PaneIndex
        switch target {
        case let .insertColumn(columnIndex):
            index = PaneIndex(
                column: min(max(columnIndex, 0), grid.columns.count - 1),
                row: 0
            )
        case let .insertRow(columnIndex, rowIndex):
            guard grid.columns.indices.contains(columnIndex) else {
                return nil
            }
            let rowCount = grid.columns[columnIndex].rowFractions.count
            index = PaneIndex(
                column: columnIndex,
                row: min(max(rowIndex, 0), rowCount - 1)
            )
        case let .existingPane(paneIndex):
            index = paneIndex
        }

        guard grid.columns.indices.contains(index.column),
              grid.columns[index.column].rowFractions.indices
                .contains(index.row) else {
            return nil
        }
        return index
    }

    /// Capacity checks reject only structurally invalid or geometrically infeasible insertions.
    public static func allows(
        _ target: SplitGridDropTarget,
        grid: SplitGridSnapshot,
        containerSize: CGSize
    ) -> Bool {
        switch target {
        case let .insertColumn(index):
            guard index >= 0, index <= grid.columns.count else { return false }
            return grid.columns.count
                < maxColumnCount(forContainerWidth: containerSize.width)

        case let .insertRow(columnIndex, rowIndex):
            guard grid.columns.indices.contains(columnIndex) else {
                return false
            }
            let rowCount = grid.columns[columnIndex].rowFractions.count
            guard rowIndex >= 0, rowIndex <= rowCount else { return false }
            return rowCount
                < maxRowCount(forContainerHeight: containerSize.height)

        case let .existingPane(index):
            guard grid.columns.indices.contains(index.column) else {
                return false
            }
            return grid.columns[index.column].rowFractions.indices
                .contains(index.row)
        }
    }

    /// Moving a column divider changes only its two neighboring width shares.
    public static func resizingColumnDivider(
        _ grid: SplitGridSnapshot,
        dividerIndex: Int,
        byTranslation dx: CGFloat,
        containerWidth: CGFloat
    ) -> SplitGridSnapshot {
        guard dividerIndex >= 0,
              dividerIndex < grid.columns.count - 1 else {
            return grid
        }

        let fractions = grid.columns.map(\.widthFraction)
        let resized = SplitLayoutPolicy.fractionsResizing(
            fractions,
            dividerIndex: dividerIndex,
            byTranslation: dx,
            axisLength: containerWidth,
            minLength: minPaneWidth
        )
        var result = grid
        for index in result.columns.indices {
            result.columns[index].widthFraction = resized[index]
        }
        return result
    }

    /// Moving a row divider changes only its two neighboring height shares.
    public static func resizingRowDivider(
        _ grid: SplitGridSnapshot,
        column: Int,
        dividerIndex: Int,
        byTranslation dy: CGFloat,
        containerHeight: CGFloat
    ) -> SplitGridSnapshot {
        guard grid.columns.indices.contains(column),
              dividerIndex >= 0,
              dividerIndex < grid.columns[column].rowFractions.count - 1 else {
            return grid
        }

        var result = grid
        result.columns[column].rowFractions =
            SplitLayoutPolicy.fractionsResizing(
                grid.columns[column].rowFractions,
                dividerIndex: dividerIndex,
                byTranslation: dy,
                axisLength: containerHeight,
                minLength: minPaneHeight
            )
        return result
    }

    public struct ReclampResult: Equatable, Sendable {
        public var grid: SplitGridSnapshot
        public var overflow: [PaneIndex]

        public init(grid: SplitGridSnapshot, overflow: [PaneIndex]) {
            self.grid = grid
            self.overflow = overflow
        }
    }

    /// Removing vertical overflow first preserves the reviewed eviction order across both axes.
    public static func reclamped(
        _ grid: SplitGridSnapshot,
        containerSize: CGSize
    ) -> ReclampResult {
        guard isUsable(containerSize.width),
              isUsable(containerSize.height) else {
            return ReclampResult(
                grid: normalizedGridRemovingEmptyColumns(grid),
                overflow: []
            )
        }

        let maximumRows = maxRowCount(
            forContainerHeight: containerSize.height
        )
        var columns = grid.columns.enumerated().map {
            WorkingColumn(originalIndex: $0.offset, column: $0.element)
        }
        var overflow: [PaneIndex] = []

        for index in columns.indices {
            while columns[index].column.rowFractions.count > maximumRows {
                let rowIndex = columns[index].column.rowFractions.count - 1
                overflow.append(
                    PaneIndex(
                        column: columns[index].originalIndex,
                        row: rowIndex
                    )
                )
                columns[index].column.rowFractions =
                    SplitLayoutPolicy.fractionsRemoving(
                        at: rowIndex,
                        from: columns[index].column.rowFractions
                    )
            }
        }

        columns.removeAll { $0.column.rowFractions.isEmpty }
        normalizeColumnWidths(&columns)

        let maximumColumns = maxColumnCount(
            forContainerWidth: containerSize.width
        )
        while columns.count > maximumColumns {
            let removedColumn = columns[columns.count - 1]
            for rowIndex in removedColumn.column.rowFractions.indices.reversed() {
                overflow.append(
                    PaneIndex(
                        column: removedColumn.originalIndex,
                        row: rowIndex
                    )
                )
            }
            columns.removeLast()
            normalizeColumnWidths(&columns)
        }

        let clampedWidths = SplitLayoutPolicy.clampedToMinLength(
            fractions: columns.map(\.column.widthFraction),
            axisLength: containerSize.width,
            minLength: minPaneWidth
        )
        for index in columns.indices {
            columns[index].column.widthFraction = clampedWidths[index]
            columns[index].column.rowFractions =
                SplitLayoutPolicy.clampedToMinLength(
                    fractions: columns[index].column.rowFractions,
                    axisLength: containerSize.height,
                    minLength: minPaneHeight
                )
        }

        return ReclampResult(
            grid: SplitGridSnapshot(columns: columns.map(\.column)),
            overflow: overflow
        )
    }

    private struct WorkingColumn {
        var originalIndex: Int
        var column: SplitGridSnapshot.Column
    }

    private struct ScoredDropTarget {
        let target: SplitGridDropTarget
        var score: CGFloat
        let tieOrder: Int
    }

    private static func dropTargetsInsideColumn(
        atY y: CGFloat,
        localX: CGFloat,
        columnIndex: Int,
        columnWidth: CGFloat,
        column: SplitGridSnapshot.Column,
        containerHeight: CGFloat,
        holding heldTarget: SplitGridDropTarget?
    ) -> [SplitGridDropTarget] {
        let rowCount = column.rowFractions.count
        guard rowCount > 0 else {
            return [.insertRow(column: columnIndex, at: 0)]
        }

        let height = usableLength(containerHeight)
        guard height > 0 else {
            return [.insertRow(column: columnIndex, at: 0)]
        }

        // Clamped like the horizontal axis, so a point above or below the
        // container still ranks both axes. The clamped path reproduces the
        // corner rule on its own: at a corner both edges score 0 and the tie
        // order gives the column insertion precedence.
        let clampedY = min(max(y, 0), height)
        let heights = rowHeights(
            column: column,
            containerHeight: height
        )
        var rowStartY: CGFloat = 0

        for (rowIndex, rowHeight) in heights.enumerated() {
            let rowEndY = rowStartY + rowHeight
            guard clampedY <= rowEndY || rowIndex == heights.count - 1 else {
                rowStartY = rowEndY
                continue
            }

            let localY = min(clampedY - rowStartY, rowHeight)

            // Point distances would let a pane's shorter dimension dominate most
            // of a landscape or portrait pane. Normalizing makes every wedge
            // exactly one quarter of the pane at every aspect ratio.
            let u = localX / columnWidth
            let v = localY / rowHeight
            var edges = [
                ScoredDropTarget(
                    target: .insertColumn(at: columnIndex),
                    score: u,
                    tieOrder: 0
                ),
                ScoredDropTarget(
                    target: .insertColumn(at: columnIndex + 1),
                    score: 1 - u,
                    tieOrder: 1
                ),
                ScoredDropTarget(
                    target: .insertRow(column: columnIndex, at: rowIndex),
                    score: v,
                    tieOrder: 2
                ),
                ScoredDropTarget(
                    target: .insertRow(column: columnIndex, at: rowIndex + 1),
                    score: 1 - v,
                    tieOrder: 3
                ),
            ]
            for index in edges.indices where edges[index].target == heldTarget {
                edges[index].score -= dropHysteresisFraction
            }

            let horizontal = precedes(edges[1], edges[0], holding: heldTarget)
                ? edges[1]
                : edges[0]
            let vertical = precedes(edges[3], edges[2], holding: heldTarget)
                ? edges[3]
                : edges[2]

            // Left, right, top, bottom is a semantic tie order: horizontal
            // insertion still wins at corners, now without an artificial band.
            if precedes(vertical, horizontal, holding: heldTarget) {
                return [vertical.target, horizontal.target]
            }
            return [horizontal.target, vertical.target]
        }

        return [.insertRow(column: columnIndex, at: rowCount)]
    }

    private static func precedes(
        _ candidate: ScoredDropTarget,
        _ incumbent: ScoredDropTarget,
        holding heldTarget: SplitGridDropTarget?
    ) -> Bool {
        if candidate.score != incumbent.score {
            return candidate.score < incumbent.score
        }
        if candidate.target == heldTarget {
            return incumbent.target != heldTarget
        }
        if incumbent.target == heldTarget {
            return false
        }
        return candidate.tieOrder < incumbent.tieOrder
    }

    private static func normalizedGridRemovingEmptyColumns(
        _ grid: SplitGridSnapshot
    ) -> SplitGridSnapshot {
        let nonemptyColumns = grid.columns.filter {
            !$0.rowFractions.isEmpty
        }
        let widths = SplitLayoutPolicy.normalized(
            nonemptyColumns.map(\.widthFraction)
        )
        let columns = zip(nonemptyColumns, widths).map { column, width in
            SplitGridSnapshot.Column(
                widthFraction: width,
                rowFractions: SplitLayoutPolicy.normalized(
                    column.rowFractions
                )
            )
        }
        return SplitGridSnapshot(columns: columns)
    }

    private static func normalizeColumnWidths(
        _ columns: inout [WorkingColumn]
    ) {
        let widths = SplitLayoutPolicy.normalized(
            columns.map(\.column.widthFraction)
        )
        for index in columns.indices {
            columns[index].column.widthFraction = widths[index]
        }
    }

    private static func usableLength(_ length: CGFloat) -> CGFloat {
        guard isUsable(length) else { return 0 }
        return length
    }

    private static func isUsable(_ length: CGFloat) -> Bool {
        length.isFinite && length > 0
    }
}
