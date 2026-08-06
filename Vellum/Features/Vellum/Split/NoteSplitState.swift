import Foundation
import Observation
import VellumCore

/// Where a moved pane lands, expressed as the two insertions the grid supports.
// Staged for the pane-rearrange follow-up; no production caller yet.
enum PaneMoveDestination: Equatable, Sendable {
    case column(at: Int)
    case row(column: Int, at: Int)
}

/// The container observes lifecycle and destination properties, while the
/// floating-card leaf alone observes `location`. This read partition keeps
/// finger movement from rebuilding every hosted pane at display cadence.
@MainActor
@Observable
final class SplitDragSession {
    var lift: SplitDragLift?
    var location: CGPoint = .zero
    var resolution: SidebarDropResolution?
    var isLifted = false
    var isCommitting = false

    // Capacity refusal has no associated target in SidebarDropResolution. Keep
    // its geometric candidate separately so the dashed ghost can move only when
    // the wedge changes, without making the container observe finger location.
    var refusedTarget: SplitGridDropTarget?
    var originLocation: CGPoint = .zero
}

@MainActor
@Observable
final class SplitColumn: Identifiable {
    let id = UUID()
    var widthFraction: CGFloat
    var panes: [NotePane]

    init(pane: NotePane, widthFraction: CGFloat = 1) {
        self.widthFraction = widthFraction
        panes = [pane]
    }
}

@MainActor
@Observable
final class NoteSplitState {
    private(set) var columns: [SplitColumn] = []
    var focusedPaneID: UUID?
    var onPaneRemoved: ((UUID) -> Void)?
    var selectedTool: ToolID = .pen
    /// The tool an element selection set aside, restored when that selection ends.
    var toolBorrowedByElementSelection: ToolID?
    var activeOptionsTool: ToolID?
    var isShowingPaperOptions = false
    var squeezeEraser = SqueezeEraserController()

    var panes: [NotePane] {
        columns.flatMap(\.panes)
    }

    var focusedPane: NotePane? {
        panes.first { $0.id == focusedPaneID }
    }

    var gridSnapshot: SplitGridSnapshot {
        SplitGridSnapshot(
            columns: columns.map { column in
                SplitGridSnapshot.Column(
                    widthFraction: column.widthFraction,
                    rowFractions: column.panes.map(\.heightFraction)
                )
            }
        )
    }

    func pane(for noteID: UUID) -> NotePane? {
        panes.first { $0.noteID == noteID }
    }

    func paneIndex(of paneID: UUID) -> PaneIndex? {
        for (columnIndex, column) in columns.enumerated() {
            if let rowIndex = column.panes.firstIndex(where: { $0.id == paneID }) {
                return PaneIndex(column: columnIndex, row: rowIndex)
            }
        }
        return nil
    }

    func insertColumn(with pane: NotePane, at index: Int?) {
        let insertionIndex = min(max(index ?? columns.count, 0), columns.count)
        let fractions = SplitLayoutPolicy.fractionsInserting(
            at: insertionIndex,
            into: columns.map(\.widthFraction)
        )
        columns.insert(SplitColumn(pane: pane), at: insertionIndex)
        for columnIndex in columns.indices {
            columns[columnIndex].widthFraction = fractions[columnIndex]
        }
        focus(pane.id)
    }

    func stackPane(
        _ pane: NotePane,
        inColumn columnIndex: Int,
        at row: Int?
    ) {
        guard !columns.isEmpty else {
            insertColumn(with: pane, at: nil)
            return
        }

        let clampedColumnIndex = min(max(columnIndex, 0), columns.count - 1)
        let column = columns[clampedColumnIndex]
        let insertionIndex = min(max(row ?? column.panes.count, 0), column.panes.count)
        let fractions = SplitLayoutPolicy.fractionsInserting(
            at: insertionIndex,
            into: column.panes.map(\.heightFraction)
        )
        column.panes.insert(pane, at: insertionIndex)
        for rowIndex in column.panes.indices {
            column.panes[rowIndex].heightFraction = fractions[rowIndex]
        }
        focus(pane.id)
    }

    /// Reinserts the same `NotePane` object, so a move never reloads the note,
    /// resets the canvas, or disturbs the undo stack.
    /// Returns false when the move is a no-op so callers can skip drop feedback.
    // Staged for the pane-rearrange follow-up; no production caller yet.
    @discardableResult
    func movePane(id paneID: UUID, to destination: PaneMoveDestination) -> Bool {
        guard let source = paneIndex(of: paneID) else { return false }

        let isNoOp: Bool
        switch destination {
        case let .column(index):
            let sourceIsOnlyPane = columns[source.column].panes.count == 1
            isNoOp = sourceIsOnlyPane
                && (index == source.column || index == source.column + 1)
        case let .row(column, row):
            isNoOp = column == source.column
                && (row == source.row || row == source.row + 1)
        }

        // Detach-then-insert runs fractionsRemoving then fractionsInserting,
        // re-equalizing shares. Rejecting a null move preserves hand-tuned
        // divider fractions.
        guard !isNoOp else { return false }

        let detached = detachPane(at: source)

        // Collapsing the source shifts every later destination column left by one.
        // A row target in that source column is unreachable: its sole pane had
        // boundaries 0 and 1, and both were rejected as no-ops above.
        switch destination {
        case let .column(index):
            let adjustedIndex = detached.columnCollapsed && index > source.column
                ? index - 1
                : index
            insertColumn(with: detached.pane, at: adjustedIndex)
        case let .row(column, row):
            let adjustedColumn = detached.columnCollapsed && column > source.column
                ? column - 1
                : column
            // The detach removed source.row from this column, so every later
            // destination row resolved against the pre-move grid shifts up by one.
            let adjustedRow = !detached.columnCollapsed
                && column == source.column
                && row > source.row
                ? row - 1
                : row
            stackPane(detached.pane, inColumn: adjustedColumn, at: adjustedRow)
        }

        return true
    }

    /// The grid as it would be with the pane already lifted out, for capacity
    /// checks that must account for an emptied source column.
    func gridSnapshotRemoving(paneID: UUID) -> SplitGridSnapshot {
        guard let source = paneIndex(of: paneID) else { return gridSnapshot }

        let sourceColumn = columns[source.column]
        let rowFractions = SplitLayoutPolicy.fractionsRemoving(
            at: source.row,
            from: sourceColumn.panes.map(\.heightFraction)
        )
        var snapshotColumns = columns.map { column in
            SplitGridSnapshot.Column(
                widthFraction: column.widthFraction,
                rowFractions: column.panes.map(\.heightFraction)
            )
        }

        if rowFractions.isEmpty {
            let columnFractions = SplitLayoutPolicy.fractionsRemoving(
                at: source.column,
                from: columns.map(\.widthFraction)
            )
            snapshotColumns.remove(at: source.column)
            for columnIndex in snapshotColumns.indices {
                snapshotColumns[columnIndex].widthFraction =
                    columnFractions[columnIndex]
            }
        } else {
            snapshotColumns[source.column].rowFractions = rowFractions
        }

        return SplitGridSnapshot(columns: snapshotColumns)
    }

    func replacePane(id: UUID, with pane: NotePane) {
        guard let index = paneIndex(of: id) else { return }
        let oldPane = columns[index.column].panes[index.row]
        let oldNoteID = oldPane.noteID
        pane.heightFraction = oldPane.heightFraction
        columns[index.column].panes[index.row] = pane
        focus(pane.id)
        onPaneRemoved?(oldNoteID)
    }

    func removePane(id: UUID) {
        guard let index = paneIndex(of: id) else { return }
        let removedNoteID = columns[index.column].panes[index.row].noteID
        let removedPaneWasFocused = focusedPaneID == id
        // Only the focused pane can own a live element-selection tool borrow.
        if removedPaneWasFocused {
            let borrowedFrom = toolBorrowedByElementSelection
            toolBorrowedByElementSelection = nil
            if selectedTool == .select, let borrowedFrom {
                selectedTool = borrowedFrom
            }
        }
        let column = columns[index.column]
        let rowFractions = SplitLayoutPolicy.fractionsRemoving(
            at: index.row,
            from: column.panes.map(\.heightFraction)
        )
        column.panes.remove(at: index.row)

        if column.panes.isEmpty {
            let columnFractions = SplitLayoutPolicy.fractionsRemoving(
                at: index.column,
                from: columns.map(\.widthFraction)
            )
            columns.remove(at: index.column)
            for columnIndex in columns.indices {
                columns[columnIndex].widthFraction = columnFractions[columnIndex]
            }
        } else {
            for rowIndex in column.panes.indices {
                column.panes[rowIndex].heightFraction = rowFractions[rowIndex]
            }
        }

        if removedPaneWasFocused {
            if columns.indices.contains(index.column),
               columns[index.column].panes.indices.contains(index.row) {
                focusedPaneID = columns[index.column].panes[index.row].id
            } else if columns.indices.contains(index.column),
                      let lastPane = columns[index.column].panes.last {
                focusedPaneID = lastPane.id
            } else if !columns.isEmpty {
                let nearestColumn = min(index.column, columns.count - 1)
                focusedPaneID = columns[nearestColumn].panes.first?.id
            } else {
                focusedPaneID = nil
            }
        }
        onPaneRemoved?(removedNoteID)
    }

    private func detachPane(
        at index: PaneIndex
    ) -> (pane: NotePane, columnCollapsed: Bool) {
        // This pane is not going away, so its focus and live element-selection
        // tool borrow must survive until the same object is reinserted.
        let column = columns[index.column]
        let rowFractions = SplitLayoutPolicy.fractionsRemoving(
            at: index.row,
            from: column.panes.map(\.heightFraction)
        )
        let pane = column.panes.remove(at: index.row)
        let columnCollapsed = column.panes.isEmpty

        if columnCollapsed {
            let columnFractions = SplitLayoutPolicy.fractionsRemoving(
                at: index.column,
                from: columns.map(\.widthFraction)
            )
            columns.remove(at: index.column)
            for columnIndex in columns.indices {
                columns[columnIndex].widthFraction = columnFractions[columnIndex]
            }
        } else {
            for rowIndex in column.panes.indices {
                column.panes[rowIndex].heightFraction = rowFractions[rowIndex]
            }
        }

        return (pane, columnCollapsed)
    }

    func focus(_ id: UUID) {
        guard focusedPaneID != id else { return }
        focusedPaneID = id
    }

    func applyGrid(_ snapshot: SplitGridSnapshot) {
        guard snapshot.columns.count == columns.count,
              zip(columns, snapshot.columns).allSatisfy({
                  $0.0.panes.count == $0.1.rowFractions.count
              }) else {
            return
        }

        for columnIndex in columns.indices {
            let snapshotColumn = snapshot.columns[columnIndex]
            let column = columns[columnIndex]
            column.widthFraction = snapshotColumn.widthFraction
            for rowIndex in column.panes.indices {
                column.panes[rowIndex].heightFraction =
                    snapshotColumn.rowFractions[rowIndex]
            }
        }
    }

    func flushAll() async {
        for pane in panes {
            _ = await pane.noteModel.flushPendingSave()
        }
    }

    func closeAll() async {
        await flushAll()
        for noteID in panes.map(\.noteID) {
            onPaneRemoved?(noteID)
        }
        columns.removeAll()
        focusedPaneID = nil
    }
}
