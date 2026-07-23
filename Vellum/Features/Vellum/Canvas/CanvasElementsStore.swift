import Foundation
import Observation
import PencilKit
import UIKit
import VellumCore

@MainActor
@Observable
final class CanvasElementsStore {
    private struct Snapshot: Equatable {
        let drawingData: Data?
        let elements: [CanvasElement]
        let pages: [NotePage]?

        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.drawingData == rhs.drawingData
                && lhs.elements == rhs.elements
                && pagesEqual(lhs.pages, rhs.pages)
        }

        private static func pagesEqual(
            _ lhs: [NotePage]?,
            _ rhs: [NotePage]?
        ) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil):
                return true
            case (.some(let lhs), .some(let rhs)):
                guard lhs.count == rhs.count else { return false }
                return zip(lhs, rhs).allSatisfy { lhsPage, rhsPage in
                    lhsPage.id == rhsPage.id
                        && lhsPage.order == rhsPage.order
                        && lhsPage.plainText == rhsPage.plainText
                        && lhsPage.drawingAssetPath == rhsPage.drawingAssetPath
                        && lhsPage.background == rhsPage.background
                        && lhsPage.pdfPage == rhsPage.pdfPage
                        && lhsPage.elements == rhsPage.elements
                }
            default:
                return false
            }
        }
    }

    private(set) var elements: [CanvasElement] = []
    private(set) var imageCache: [String: UIImage] = [:]
    private(set) var imageDataCache: [String: Data] = [:]
    var canvasReference: NoteCanvasReference?
    var undoManagerOverride: UndoManager?
    var onElementsChanged: (([CanvasElement]) -> Void)?
    var pagesProvider: (() -> [NotePage])?
    var onPagesRestored: (([NotePage]) -> Void)?
    /// Fired after an undo/redo snapshot restore. Selection must be invalidated:
    /// the programmatic drawing write suppresses onExternalDrawingChange, so
    /// stroke indices held by a selection would silently go stale.
    var onSnapshotApplied: (() -> Void)?

    private var isInTransaction = false

    func hydrate(_ elements: [CanvasElement]) {
        self.elements = elements
    }

    func cacheImage(_ image: UIImage, data: Data, forAssetPath assetPath: String) {
        imageCache[assetPath] = image
        imageDataCache[assetPath] = data
    }

    func addElement(_ element: CanvasElement) {
        performTransaction("Add \(kindName(for: element))") {
            elements.append(element)
        }
    }

    func updateElement(_ element: CanvasElement) {
        performTransaction("Update Element") {
            guard let index = elements.firstIndex(where: { $0.id == element.id }) else {
                return
            }
            elements[index] = element
        }
    }

    /// Replace an element WITHOUT undo registration — the live-typing path.
    /// Fires onElementsChanged (rides the debounced autosave). No-op if id absent.
    func updateElementLive(_ element: CanvasElement) {
        guard let index = elements.firstIndex(where: { $0.id == element.id }) else { return }
        elements[index] = element
        onElementsChanged?(elements)
    }

    /// Remove an element WITHOUT undo registration — pairs with registerEditingSessionUndo.
    /// Fires onElementsChanged (rides the debounced autosave). No-op if id absent.
    func removeElementLive(id: UUID) {
        guard elements.contains(where: { $0.id == id }) else { return }
        elements.removeAll { $0.id == id }
        onElementsChanged?(elements)
    }

    /// Register a single undo step covering an editing session that already applied its changes
    /// via updateElementLive. `previousElements` is the elements array captured at session start.
    /// No-op if the resulting before/after snapshots are equal (i.e. nothing actually changed).
    func registerEditingSessionUndo(from previousElements: [CanvasElement], label: String) {
        let currentSnapshot = snapshot()
        let before = Snapshot(
            drawingData: currentSnapshot.drawingData,
            elements: previousElements,
            pages: currentSnapshot.pages
        )
        guard before != currentSnapshot else { return }
        guard let undoManager = undoManagerOverride ?? canvasReference?.canvasView?.undoManager else {
            return
        }
        registerUndo(
            on: undoManager,
            applying: before,
            inverse: currentSnapshot,
            label: label
        )
    }

    func removeElement(id: UUID) {
        performTransaction("Remove Element") {
            elements.removeAll { $0.id == id }
        }
    }

    /// The ONLY sanctioned way to write canvasView.drawing. Must be called inside performTransaction's body.
    func mutateDrawing(_ mutate: (inout PKDrawing) -> Void) {
        guard isInTransaction else {
            assertionFailure("mutateDrawing must be called inside performTransaction")
            return
        }
        guard let canvasView = canvasReference?.canvasView else { return }
        var drawing = canvasView.drawing
        mutate(&drawing)
        canvasView.drawing = drawing
    }

    func replaceAllElements(_ elements: [CanvasElement]) {
        guard isInTransaction else {
            assertionFailure("replaceAllElements must be called inside performTransaction")
            return
        }
        self.elements = elements
    }

    func performTransaction(_ label: String, _ body: () -> Void) {
        guard !isInTransaction else {
            body()
            return
        }

        let coordinator = canvasReference?.coordinator
        coordinator?.beginProgrammaticChange()

        let before = snapshot()
        isInTransaction = true
        body()
        isInTransaction = false
        let after = snapshot()

        if let canvasView = canvasReference?.canvasView {
            coordinator?.endProgrammaticChange(canvasView)
        }

        if before != after,
           let undoManager = undoManagerOverride ?? canvasReference?.canvasView?.undoManager {
            registerUndo(
                on: undoManager,
                applying: before,
                inverse: after,
                label: label
            )
        }

        onElementsChanged?(elements)
    }

    private func snapshot() -> Snapshot {
        Snapshot(
            drawingData: canvasReference?.canvasView?.drawing.dataRepresentation(),
            elements: elements,
            pages: pagesProvider?()
        )
    }

    private func apply(_ snapshot: Snapshot) {
        if let canvasView = canvasReference?.canvasView,
           snapshot.drawingData != canvasView.drawing.dataRepresentation(),
           let drawingData = snapshot.drawingData,
           let drawing = try? PKDrawing(data: drawingData) {
            let coordinator = canvasReference?.coordinator
            coordinator?.beginProgrammaticChange()
            canvasView.drawing = drawing
            coordinator?.endProgrammaticChange(canvasView)
        }

        elements = snapshot.elements
        if let pages = snapshot.pages {
            onPagesRestored?(pages)
        }
        onElementsChanged?(elements)
        onSnapshotApplied?()
    }

    private func registerUndo(
        on undoManager: UndoManager,
        applying snapshot: Snapshot,
        inverse: Snapshot,
        label: String
    ) {
        undoManager.registerUndo(withTarget: self) { [weak undoManager] store in
            guard let undoManager else { return }
            store.apply(snapshot)
            store.registerUndo(
                on: undoManager,
                applying: inverse,
                inverse: snapshot,
                label: label
            )
        }
        undoManager.setActionName(label)
    }

    private func kindName(for element: CanvasElement) -> String {
        switch element.content {
        case .text:
            "Text Box"
        case .image:
            "Image"
        case .unknown:
            "Object"
        }
    }
}
