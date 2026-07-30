import Foundation
import Observation
import VellumCore

@MainActor
@Observable
final class NoteSplitState {
    private(set) var panes: [NotePane] = []
    var focusedPaneID: UUID?
    var selectedTool: ToolID = .pen
    var activeOptionsTool: ToolID?
    var squeezeEraser = SqueezeEraserController()

    var focusedPane: NotePane? {
        panes.first { $0.id == focusedPaneID }
    }

    func pane(for noteID: UUID) -> NotePane? {
        panes.first { $0.noteID == noteID }
    }

    func insertPane(_ pane: NotePane, at index: Int?) {
        let insertionIndex = min(max(index ?? panes.count, 0), panes.count)
        let fractions = SplitLayoutPolicy.fractionsInserting(
            at: insertionIndex,
            into: panes.map(\.widthFraction)
        )
        panes.insert(pane, at: insertionIndex)
        applyFractions(fractions)
        focus(pane.id)
    }

    func replacePane(id: UUID, with pane: NotePane) {
        guard let index = panes.firstIndex(where: { $0.id == id }) else { return }
        pane.widthFraction = panes[index].widthFraction
        panes[index] = pane
        focus(pane.id)
    }

    func removePane(id: UUID) {
        guard let index = panes.firstIndex(where: { $0.id == id }) else { return }
        let removedPaneWasFocused = focusedPaneID == id
        let fractions = SplitLayoutPolicy.fractionsRemoving(
            at: index,
            from: panes.map(\.widthFraction)
        )
        panes.remove(at: index)
        applyFractions(fractions)

        guard !panes.isEmpty else {
            focusedPaneID = nil
            return
        }
        if removedPaneWasFocused {
            focusedPaneID = panes.indices.contains(index) ? panes[index].id : panes.last?.id
        }
    }

    func focus(_ id: UUID) {
        focusedPaneID = id
    }

    func applyFractions(_ fractions: [CGFloat]) {
        guard fractions.count == panes.count else { return }
        zip(panes, fractions).forEach { pane, fraction in
            pane.widthFraction = fraction
        }
    }

    func flushAll() async {
        for pane in panes {
            _ = await pane.noteModel.flushPendingSave()
        }
    }

    func closeAll() async {
        await flushAll()
        panes.removeAll()
        focusedPaneID = nil
    }
}
