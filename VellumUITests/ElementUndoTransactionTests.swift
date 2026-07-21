import Foundation
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class ElementUndoTransactionTests: XCTestCase {
    func testAddUndoAndRedoNotifyWithExpectedElements() {
        let (store, undoManager) = makeStore()
        let element = makeElement(text: "Undo me")
        var changes: [[CanvasElement]] = []
        store.onElementsChanged = { changes.append($0) }

        store.addElement(element)

        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        XCTAssertTrue(store.elements.isEmpty)
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()
        XCTAssertEqual(store.elements, [element])
        XCTAssertEqual(changes, [[element], [], [element]])
    }

    func testNoOpTransactionDoesNotRegisterUndo() {
        let (store, undoManager) = makeStore()

        store.performTransaction("No-op") {}

        XCTAssertFalse(undoManager.canUndo)
    }

    func testNestedTransactionsRegisterOneUndoForAllChanges() {
        let (store, undoManager) = makeStore()
        let firstElement = makeElement(text: "First")
        let secondElement = makeElement(text: "Second")

        store.performTransaction("Outer") {
            store.addElement(firstElement)
            store.addElement(secondElement)
        }

        XCTAssertEqual(store.elements, [firstElement, secondElement])
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertTrue(store.elements.isEmpty)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(undoManager.canRedo)
    }

    func testAddElementUsesKindSpecificUndoActionNames() {
        let (textStore, textUndoManager) = makeStore()
        textStore.addElement(makeElement(text: "Text"))
        XCTAssertEqual(textUndoManager.undoActionName, "Add Text Box")

        let (imageStore, imageUndoManager) = makeStore()
        imageStore.addElement(makeImageElement())
        XCTAssertEqual(imageUndoManager.undoActionName, "Add Image")
    }

    func testMutationWithoutUndoManagerStillAppliesAndNotifies() {
        let store = CanvasElementsStore()
        let element = makeElement(text: "No manager")
        var changes: [[CanvasElement]] = []
        store.onElementsChanged = { changes.append($0) }

        store.addElement(element)

        XCTAssertEqual(store.elements, [element])
        XCTAssertEqual(changes, [[element]])
    }

    func testLiveEditingSessionRegistersOneUndoStepAndSkipsNoOp() {
        let (store, undoManager) = makeStore()
        let initialElement = makeElement(text: "Before")
        store.addElement(initialElement)
        undoManager.removeAllActions()
        let baseline = store.elements

        for typedText in ["F", "Fi", "Final"] {
            var updated = initialElement
            updated.content = .text(
                TextBoxContent(
                    text: typedText,
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            )
            store.updateElementLive(updated)
        }
        let finalElements = store.elements

        XCTAssertFalse(undoManager.canUndo)
        store.registerEditingSessionUndo(from: baseline, label: "Edit Text")

        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Edit Text")

        store.registerEditingSessionUndo(from: store.elements, label: "No-op")
        XCTAssertEqual(undoManager.undoActionName, "Edit Text")

        undoManager.undo()

        XCTAssertEqual(store.elements, baseline)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(undoManager.canRedo)
        XCTAssertEqual(undoManager.redoActionName, "Edit Text")

        undoManager.redo()

        XCTAssertEqual(store.elements, finalElements)
        XCTAssertEqual(undoManager.undoActionName, "Edit Text")
    }

    func testLiveEditingSessionDeletionRestoresOriginalTextOnUndo() {
        let (store, undoManager) = makeStore()
        let initialElement = makeElement(text: "hello")
        store.addElement(initialElement)
        undoManager.removeAllActions()
        let baseline = store.elements

        var emptiedElement = initialElement
        emptiedElement.content = .text(
            TextBoxContent(
                text: "",
                fontSize: 18,
                color: CodableColor(red: 0, green: 0, blue: 0)
            )
        )
        store.updateElementLive(emptiedElement)
        store.removeElementLive(id: initialElement.id)
        store.registerEditingSessionUndo(from: baseline, label: "Remove Text Box")

        XCTAssertTrue(store.elements.isEmpty)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Remove Text Box")

        undoManager.undo()

        XCTAssertEqual(store.elements, baseline)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()

        XCTAssertTrue(store.elements.isEmpty)
    }

    func testNewEmptyTextBoxDeletionRegistersUndoAboveAdd() {
        let (store, undoManager) = makeStore()
        // Model production, where the Add and the later blur/deletion happen on separate
        // run-loop turns and are naturally separate undo groups: disable per-event grouping
        // and group each step explicitly (groupsByEvent would otherwise coalesce these two
        // same-turn registrations into a single undo group in this synchronous test).
        undoManager.groupsByEvent = false
        let emptyBox = makeElement(text: "")

        undoManager.beginUndoGrouping()
        store.addElement(emptyBox)
        undoManager.endUndoGrouping()
        let baseline = store.elements

        undoManager.beginUndoGrouping()
        store.removeElementLive(id: emptyBox.id)
        store.registerEditingSessionUndo(from: baseline, label: "Remove Text Box")
        undoManager.endUndoGrouping()

        XCTAssertTrue(store.elements.isEmpty)

        undoManager.undo()
        XCTAssertEqual(store.elements, baseline)

        undoManager.undo()
        XCTAssertTrue(store.elements.isEmpty)

        undoManager.redo()
        XCTAssertEqual(store.elements, baseline)

        undoManager.redo()
        XCTAssertTrue(store.elements.isEmpty)
    }

    func testRemoveElementLiveWithUnknownIDIsNoOp() {
        let (store, undoManager) = makeStore()
        let element = makeElement(text: "Existing")
        store.addElement(element)
        undoManager.removeAllActions()
        let expectedElements = store.elements
        var changes: [[CanvasElement]] = []
        store.onElementsChanged = { changes.append($0) }

        store.removeElementLive(id: UUID())

        XCTAssertEqual(store.elements, expectedElements)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertFalse(undoManager.canUndo)
    }

    private func makeStore() -> (CanvasElementsStore, UndoManager) {
        let store = CanvasElementsStore()
        let undoManager = UndoManager()
        store.undoManagerOverride = undoManager
        return (store, undoManager)
    }

    private func makeElement(text: String) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: text,
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: CanvasRect(x: 10, y: 20, width: 100, height: 40)
        )
    }

    private func makeImageElement() -> CanvasElement {
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: "images/undo.png",
                    originalPixelSize: CanvasSize(width: 200, height: 100)
                )
            ),
            frame: CanvasRect(x: 20, y: 30, width: 200, height: 100)
        )
    }
}
