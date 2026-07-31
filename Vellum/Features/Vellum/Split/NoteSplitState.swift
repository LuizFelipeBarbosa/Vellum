import Foundation
import Observation
import VellumCore

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

    func replacePane(id: UUID, with pane: NotePane) {
        guard let index = paneIndex(of: id) else { return }
        let oldPane = columns[index.column].panes[index.row]
        pane.heightFraction = oldPane.heightFraction
        columns[index.column].panes[index.row] = pane
        focus(pane.id)
    }

    func removePane(id: UUID) {
        guard let index = paneIndex(of: id) else { return }
        let removedPaneWasFocused = focusedPaneID == id
        // Only the focused pane can own a live element-selection tool borrow.
        if removedPaneWasFocused {
            toolBorrowedByElementSelection = nil
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

        guard removedPaneWasFocused else { return }
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
        columns.removeAll()
        focusedPaneID = nil
    }
}
