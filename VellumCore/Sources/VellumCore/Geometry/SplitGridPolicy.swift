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
    case existingPane(PaneIndex)
}

public enum SplitGridPolicy {
    public static let minPaneWidth: CGFloat = 320
    public static let minPaneHeight: CGFloat = 280
    public static let edgeZoneFraction: CGFloat = 0.25
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

    /// Edge zones favor insertion, with horizontal insertion taking precedence at corners.
    public static func dropTarget(
        at point: CGPoint,
        grid: SplitGridSnapshot,
        containerSize: CGSize
    ) -> SplitGridDropTarget {
        guard !grid.columns.isEmpty,
              !point.x.isNaN,
              !point.y.isNaN else {
            return .insertColumn(at: 0)
        }

        let width = usableLength(containerSize.width)
        if point.x <= 0 {
            return .insertColumn(at: 0)
        }
        if point.x >= width {
            return .insertColumn(at: grid.columns.count)
        }

        let widths = columnWidths(grid: grid, containerWidth: width)
        var columnStartX: CGFloat = 0

        for (columnIndex, columnWidth) in widths.enumerated() {
            let columnEndX = columnStartX + columnWidth
            guard point.x <= columnEndX else {
                columnStartX = columnEndX
                continue
            }

            let localX = point.x - columnStartX
            if localX <= columnWidth * edgeZoneFraction {
                return .insertColumn(at: columnIndex)
            }
            if localX >= columnWidth * (1 - edgeZoneFraction) {
                return .insertColumn(at: columnIndex + 1)
            }

            return rowDropTarget(
                atY: point.y,
                columnIndex: columnIndex,
                column: grid.columns[columnIndex],
                containerHeight: containerSize.height
            )
        }

        return .insertColumn(at: grid.columns.count)
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

    private static func rowDropTarget(
        atY y: CGFloat,
        columnIndex: Int,
        column: SplitGridSnapshot.Column,
        containerHeight: CGFloat
    ) -> SplitGridDropTarget {
        let rowCount = column.rowFractions.count
        guard rowCount > 0 else {
            return .insertRow(column: columnIndex, at: 0)
        }

        let height = usableLength(containerHeight)
        if y <= 0 {
            return .insertRow(column: columnIndex, at: 0)
        }
        if y >= height {
            return .insertRow(column: columnIndex, at: rowCount)
        }

        let heights = rowHeights(
            column: column,
            containerHeight: height
        )
        var rowStartY: CGFloat = 0

        for (rowIndex, rowHeight) in heights.enumerated() {
            let rowEndY = rowStartY + rowHeight
            guard y <= rowEndY else {
                rowStartY = rowEndY
                continue
            }

            let localY = y - rowStartY
            if localY <= rowHeight * edgeZoneFraction {
                return .insertRow(column: columnIndex, at: rowIndex)
            }
            if localY >= rowHeight * (1 - edgeZoneFraction) {
                return .insertRow(column: columnIndex, at: rowIndex + 1)
            }
            return .existingPane(
                PaneIndex(column: columnIndex, row: rowIndex)
            )
        }

        return .insertRow(column: columnIndex, at: rowCount)
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
