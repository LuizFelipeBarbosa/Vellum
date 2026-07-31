import Foundation
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class NoteSplitStateTests: XCTestCase {
    func testInsertColumnSupportsTrailingLeadingAndMiddlePositions() {
        let container = makeContainer()
        let first = makePane(container: container)
        let trailing = makePane(container: container)
        let leading = makePane(container: container)
        let middle = makePane(container: container)
        let state = NoteSplitState()

        state.insertColumn(with: first, at: nil)
        XCTAssertEqual(state.columns.map { $0.panes[0].id }, [first.id])
        XCTAssertEqual(state.columns[0].widthFraction, 1, accuracy: 0.0001)
        XCTAssertEqual(state.focusedPaneID, first.id)

        state.insertColumn(with: trailing, at: nil)
        XCTAssertEqual(
            state.columns.map { $0.panes[0].id },
            [first.id, trailing.id]
        )
        assertFractions(state.columns.map(\.widthFraction), equalTo: [0.5, 0.5])
        XCTAssertEqual(state.focusedPaneID, trailing.id)

        state.insertColumn(with: leading, at: 0)
        XCTAssertEqual(
            state.columns.map { $0.panes[0].id },
            [leading.id, first.id, trailing.id]
        )
        assertFractions(
            state.columns.map(\.widthFraction),
            equalTo: [1 / 3, 1 / 3, 1 / 3]
        )
        XCTAssertEqual(state.focusedPaneID, leading.id)

        state.insertColumn(with: middle, at: 2)
        XCTAssertEqual(
            state.columns.map { $0.panes[0].id },
            [leading.id, first.id, middle.id, trailing.id]
        )
        assertFractions(
            state.columns.map(\.widthFraction),
            equalTo: [0.25, 0.25, 0.25, 0.25]
        )
        XCTAssertEqual(state.focusedPaneID, middle.id)
    }

    func testStackPaneUsesRowFractionsAndFallsBackOnAnEmptyGrid() {
        let container = makeContainer()
        let first = makePane(container: container)
        let bottom = makePane(container: container)
        let top = makePane(container: container)
        let state = NoteSplitState()

        state.stackPane(first, inColumn: 42, at: nil)
        XCTAssertEqual(state.columns.count, 1)
        XCTAssertEqual(state.columns[0].panes.map(\.id), [first.id])
        XCTAssertEqual(state.focusedPaneID, first.id)

        state.stackPane(bottom, inColumn: 0, at: nil)
        XCTAssertEqual(state.columns[0].panes.map(\.id), [first.id, bottom.id])
        assertFractions(
            state.columns[0].panes.map(\.heightFraction),
            equalTo: [0.5, 0.5]
        )
        XCTAssertEqual(state.focusedPaneID, bottom.id)

        state.stackPane(top, inColumn: 0, at: 0)
        XCTAssertEqual(
            state.columns[0].panes.map(\.id),
            [top.id, first.id, bottom.id]
        )
        assertFractions(
            state.columns[0].panes.map(\.heightFraction),
            equalTo: [1 / 3, 1 / 3, 1 / 3]
        )
        XCTAssertEqual(state.focusedPaneID, top.id)
    }

    func testReplacePanePreservesPositionAndHeightFraction() {
        let container = makeContainer()
        let top = makePane(container: container)
        let replaced = makePane(container: container)
        let replacement = makePane(container: container)
        let state = NoteSplitState()
        state.insertColumn(with: top, at: nil)
        state.stackPane(replaced, inColumn: 0, at: nil)
        state.applyGrid(
            SplitGridSnapshot(columns: [
                .init(widthFraction: 1, rowFractions: [0.3, 0.7]),
            ])
        )

        state.replacePane(id: replaced.id, with: replacement)

        XCTAssertEqual(state.columns[0].panes.map(\.id), [top.id, replacement.id])
        XCTAssertEqual(replacement.heightFraction, 0.7, accuracy: 0.0001)
        XCTAssertEqual(state.focusedPaneID, replacement.id)
        XCTAssertEqual(
            state.paneIndex(of: replacement.id),
            PaneIndex(column: 0, row: 1)
        )
    }

    func testRemovePaneRenormalizesRowsAndUsesSameIndexThenLastRow() {
        let container = makeContainer()
        let top = makePane(container: container)
        let middle = makePane(container: container)
        let bottom = makePane(container: container)
        let state = NoteSplitState()
        state.insertColumn(with: top, at: nil)
        state.stackPane(middle, inColumn: 0, at: nil)
        state.stackPane(bottom, inColumn: 0, at: nil)

        state.focus(middle.id)
        state.removePane(id: middle.id)

        XCTAssertEqual(state.columns[0].panes.map(\.id), [top.id, bottom.id])
        assertFractions(
            state.columns[0].panes.map(\.heightFraction),
            equalTo: [0.5, 0.5]
        )
        XCTAssertEqual(state.focusedPaneID, bottom.id)

        state.removePane(id: bottom.id)

        XCTAssertEqual(state.columns[0].panes.map(\.id), [top.id])
        XCTAssertEqual(state.columns[0].panes[0].heightFraction, 1, accuracy: 0.0001)
        XCTAssertEqual(state.focusedPaneID, top.id)
    }

    func testRemovePaneClearsBorrowedSelectionToolWhenRemovingFocusedPane() {
        let container = makeContainer()
        let pane = makePane(container: container)
        let state = NoteSplitState()
        state.insertColumn(with: pane, at: nil)
        state.toolBorrowedByElementSelection = .pen

        state.removePane(id: pane.id)

        XCTAssertNil(state.toolBorrowedByElementSelection)
    }

    func testRemovingLastPaneCollapsesColumnAndUsesNearestFocus() {
        let container = makeContainer()
        let first = makePane(container: container)
        let middle = makePane(container: container)
        let last = makePane(container: container)
        let state = NoteSplitState()
        state.insertColumn(with: first, at: nil)
        state.insertColumn(with: middle, at: nil)
        state.insertColumn(with: last, at: nil)
        state.applyGrid(
            SplitGridSnapshot(columns: [
                .init(widthFraction: 0.2, rowFractions: [1]),
                .init(widthFraction: 0.3, rowFractions: [1]),
                .init(widthFraction: 0.5, rowFractions: [1]),
            ])
        )

        state.focus(middle.id)
        state.removePane(id: middle.id)

        XCTAssertEqual(
            state.columns.map { $0.panes[0].id },
            [first.id, last.id]
        )
        assertFractions(
            state.columns.map(\.widthFraction),
            equalTo: [2 / 7, 5 / 7]
        )
        XCTAssertEqual(state.focusedPaneID, last.id)

        state.removePane(id: last.id)

        XCTAssertEqual(state.columns.map { $0.panes[0].id }, [first.id])
        XCTAssertEqual(state.columns[0].widthFraction, 1, accuracy: 0.0001)
        XCTAssertEqual(state.focusedPaneID, first.id)

        state.removePane(id: first.id)

        XCTAssertTrue(state.columns.isEmpty)
        XCTAssertTrue(state.panes.isEmpty)
        XCTAssertNil(state.focusedPaneID)
    }

    func testFocusingTheFocusedPaneKeepsStateConsistent() {
        let container = makeContainer()
        let pane = makePane(container: container)
        let state = NoteSplitState()
        state.insertColumn(with: pane, at: nil)
        let snapshot = state.gridSnapshot

        state.focus(pane.id)
        state.focus(pane.id)

        XCTAssertEqual(state.focusedPaneID, pane.id)
        XCTAssertEqual(state.focusedPane?.id, pane.id)
        XCTAssertEqual(state.gridSnapshot, snapshot)
    }

    func testApplyGridRequiresAnExactStructuralMatch() {
        let container = makeContainer()
        let top = makePane(container: container)
        let bottom = makePane(container: container)
        let right = makePane(container: container)
        let state = NoteSplitState()
        state.insertColumn(with: top, at: nil)
        state.stackPane(bottom, inColumn: 0, at: nil)
        state.insertColumn(with: right, at: nil)

        let matching = SplitGridSnapshot(columns: [
            .init(widthFraction: 0.4, rowFractions: [0.25, 0.75]),
            .init(widthFraction: 0.6, rowFractions: [1]),
        ])
        state.applyGrid(matching)
        XCTAssertEqual(state.gridSnapshot, matching)

        state.applyGrid(
            SplitGridSnapshot(columns: [
                .init(widthFraction: 1, rowFractions: [1]),
            ])
        )
        XCTAssertEqual(state.gridSnapshot, matching)

        state.applyGrid(
            SplitGridSnapshot(columns: [
                .init(widthFraction: 0.5, rowFractions: [1]),
                .init(widthFraction: 0.5, rowFractions: [0.5, 0.5]),
            ])
        )
        XCTAssertEqual(state.gridSnapshot, matching)
    }

    func testReclampOverflowIDsCanBeRemovedWithoutStaleIndexes() {
        let container = makeContainer()
        let topLeft = makePane(container: container)
        let bottomLeft = makePane(container: container)
        let topMiddle = makePane(container: container)
        let bottomMiddle = makePane(container: container)
        let topRight = makePane(container: container)
        let bottomRight = makePane(container: container)
        let state = NoteSplitState()
        state.insertColumn(with: topLeft, at: nil)
        state.stackPane(bottomLeft, inColumn: 0, at: nil)
        state.insertColumn(with: topMiddle, at: nil)
        state.stackPane(bottomMiddle, inColumn: 1, at: nil)
        state.insertColumn(with: topRight, at: nil)
        state.stackPane(bottomRight, inColumn: 2, at: nil)

        let result = SplitGridPolicy.reclamped(
            state.gridSnapshot,
            containerSize: CGSize(width: 640, height: 280)
        )
        let overflowPaneIDs = result.overflow.compactMap { index -> UUID? in
            guard state.columns.indices.contains(index.column),
                  state.columns[index.column].panes.indices.contains(index.row) else {
                return nil
            }
            return state.columns[index.column].panes[index.row].id
        }

        XCTAssertEqual(
            overflowPaneIDs,
            [bottomLeft.id, bottomMiddle.id, bottomRight.id, topRight.id]
        )

        for paneID in overflowPaneIDs {
            state.removePane(id: paneID)
        }
        state.applyGrid(result.grid)

        XCTAssertEqual(state.columns.count, 2)
        XCTAssertEqual(state.columns[0].panes.map(\.id), [topLeft.id])
        XCTAssertEqual(state.columns[1].panes.map(\.id), [topMiddle.id])
        assertFractions(state.columns.map(\.widthFraction), equalTo: [0.5, 0.5])
        assertFractions(
            state.panes.map(\.heightFraction),
            equalTo: [1, 1]
        )
    }

    func testResizeOverflowRecomputesLiveGridAfterDebounce() async throws {
        let container = makeContainer()
        let first = makePane(container: container)
        let middle = makePane(container: container)
        let trailing = makePane(container: container)
        let model = VellumAppModel(container: container, arguments: [])
        model.split.insertColumn(with: first, at: nil)
        model.split.insertColumn(with: middle, at: nil)
        model.split.insertColumn(with: trailing, at: nil)
        let containerSize = CGSize(width: 640, height: 560)

        XCTAssertEqual(
            SplitGridPolicy.reclamped(
                model.split.gridSnapshot,
                containerSize: containerSize
            ).overflow,
            [PaneIndex(column: 2, row: 0)]
        )

        model.handleSplitContainerResize(containerSize)
        model.split.removePane(id: first.id)
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(model.split.panes.map(\.id), [middle.id, trailing.id])
        assertFractions(
            model.split.columns.map(\.widthFraction),
            equalTo: [0.5, 0.5]
        )
        XCTAssertNil(model.toast)
    }

    func testHandleSplitContainerResizeShrinkEvictsOverflowAndRenormalizesFractions()
        async throws {
        let container = makeContainer()
        let first = makePane(container: container)
        let middle = makePane(container: container)
        let trailing = makePane(container: container)
        let model = VellumAppModel(container: container, arguments: [])
        model.split.insertColumn(with: first, at: nil)
        model.split.insertColumn(with: middle, at: nil)
        model.split.insertColumn(with: trailing, at: nil)
        let containerSize = CGSize(width: 640, height: 560)

        XCTAssertEqual(
            SplitGridPolicy.reclamped(
                model.split.gridSnapshot,
                containerSize: containerSize
            ).overflow,
            [PaneIndex(column: 2, row: 0)]
        )

        model.handleSplitContainerResize(containerSize)

        let evictionFinished = try await waitUntil {
            model.split.panes.map(\.id) == [first.id, middle.id]
                && model.toast?.text == "Closed 1 pane to fit"
        }
        XCTAssertTrue(
            evictionFinished,
            "resize overflow eviction did not finish"
        )

        // flushPendingSave() has no injectable observer, so this verifies the
        // externally observable consequences rather than flush-before-remove itself.
        XCTAssertFalse(model.split.panes.contains { $0.id == trailing.id })
        assertFractions(
            model.split.columns.map(\.widthFraction),
            equalTo: [0.5, 0.5]
        )
        for column in model.split.columns {
            assertFractions(
                column.panes.map(\.heightFraction),
                equalTo: [1]
            )
        }
        XCTAssertEqual(
            model.split.columns.map(\.widthFraction).reduce(0, +),
            1,
            accuracy: 0.0001
        )
        for column in model.split.columns {
            XCTAssertEqual(
                column.panes.map(\.heightFraction).reduce(0, +),
                1,
                accuracy: 0.0001
            )
        }
        XCTAssertEqual(model.toast?.text, "Closed 1 pane to fit")
    }

    func testHandleSplitContainerResizeEvictsBottomRowsBeforeTrailingColumns()
        async throws {
        let container = makeContainer()
        let topLeft = makePane(container: container)
        let bottomLeft = makePane(container: container)
        let topMiddle = makePane(container: container)
        let bottomMiddle = makePane(container: container)
        let topRight = makePane(container: container)
        let bottomRight = makePane(container: container)
        let model = VellumAppModel(container: container, arguments: [])
        model.split.insertColumn(with: topLeft, at: nil)
        model.split.stackPane(bottomLeft, inColumn: 0, at: nil)
        model.split.insertColumn(with: topMiddle, at: nil)
        model.split.stackPane(bottomMiddle, inColumn: 1, at: nil)
        model.split.insertColumn(with: topRight, at: nil)
        model.split.stackPane(bottomRight, inColumn: 2, at: nil)
        let containerSize = CGSize(width: 640, height: 280)
        let overflowResult = SplitGridPolicy.reclamped(
            model.split.gridSnapshot,
            containerSize: containerSize
        )
        let overflowPaneIDs = overflowResult.overflow.compactMap { index -> UUID? in
            guard model.split.columns.indices.contains(index.column),
                  model.split.columns[index.column].panes.indices.contains(index.row)
            else {
                return nil
            }
            return model.split.columns[index.column].panes[index.row].id
        }

        XCTAssertEqual(
            overflowPaneIDs,
            [bottomLeft.id, bottomMiddle.id, bottomRight.id, topRight.id]
        )

        model.handleSplitContainerResize(containerSize)

        let evictionFinished = try await waitUntil {
            model.split.panes.map(\.id) == [topLeft.id, topMiddle.id]
                && model.toast?.text == "Closed 4 panes to fit"
        }
        XCTAssertTrue(
            evictionFinished,
            "ordered resize overflow eviction did not finish"
        )
        XCTAssertEqual(
            model.split.panes.map(\.id),
            [topLeft.id, topMiddle.id]
        )
        assertFractions(
            model.split.columns.map(\.widthFraction),
            equalTo: [0.5, 0.5]
        )
        XCTAssertEqual(model.toast?.text, "Closed 4 panes to fit")
    }

    func testHandleSplitContainerResizeThatStillFitsEvictsNothing() async throws {
        let container = makeContainer()
        let first = makePane(container: container)
        let trailing = makePane(container: container)
        let model = VellumAppModel(container: container, arguments: [])
        model.split.insertColumn(with: first, at: nil)
        model.split.insertColumn(with: trailing, at: nil)
        let containerSize = CGSize(width: 1_024, height: 768)
        let originalPaneIDs = model.split.panes.map(\.id)

        XCTAssertTrue(
            SplitGridPolicy.reclamped(
                model.split.gridSnapshot,
                containerSize: containerSize
            ).overflow.isEmpty
        )

        model.handleSplitContainerResize(containerSize)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(model.split.panes.map(\.id), originalPaneIDs)
        assertFractions(
            model.split.columns.map(\.widthFraction),
            equalTo: [0.5, 0.5]
        )
        XCTAssertNil(model.toast)
    }

    func testHandleSplitContainerResizeDebouncesEviction() async throws {
        let container = makeContainer()
        let first = makePane(container: container)
        let middle = makePane(container: container)
        let trailing = makePane(container: container)
        let model = VellumAppModel(container: container, arguments: [])
        model.split.insertColumn(with: first, at: nil)
        model.split.insertColumn(with: middle, at: nil)
        model.split.insertColumn(with: trailing, at: nil)
        let containerSize = CGSize(width: 640, height: 560)
        let originalPaneIDs = model.split.panes.map(\.id)

        XCTAssertFalse(
            SplitGridPolicy.reclamped(
                model.split.gridSnapshot,
                containerSize: containerSize
            ).overflow.isEmpty
        )

        model.handleSplitContainerResize(containerSize)

        XCTAssertEqual(model.split.panes.map(\.id), originalPaneIDs)
        XCTAssertTrue(model.split.panes.contains { $0.id == trailing.id })

        let evictionFinished = try await waitUntil {
            !model.split.panes.contains { $0.id == trailing.id }
        }
        XCTAssertTrue(
            evictionFinished,
            "resize overflow eviction did not fire after the debounce"
        )
        XCTAssertEqual(model.split.panes.map(\.id), [first.id, middle.id])
    }

    private func makeContainer() -> AppContainer {
        AppContainer.live(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
    }

    private func makePane(container: AppContainer) -> NotePane {
        NotePane(
            noteModel: NoteScreenModel(
                noteID: UUID(),
                container: container,
                onNoteChanged: { _ in }
            )
        )
    }

    private func assertFractions(
        _ actual: [CGFloat],
        equalTo expected: [CGFloat],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualFraction, expectedFraction) in zip(actual, expected) {
            XCTAssertEqual(
                actualFraction,
                expectedFraction,
                accuracy: 0.0001,
                file: file,
                line: line
            )
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
