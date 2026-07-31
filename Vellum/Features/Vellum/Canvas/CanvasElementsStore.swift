import Foundation
import Observation
import PencilKit
import UIKit
import VellumCore

@MainActor
@Observable
final class CanvasElementsStore {
    struct NoteShape: Equatable {
        let portraitAspectRatio: Double
        let orientation: PageOrientation
    }

    fileprivate struct Snapshot: Equatable {
        let drawingData: Data?
        let elements: [CanvasElement]
        let noteShape: NoteShape?
        let pages: [NotePage]?

        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.drawingData == rhs.drawingData
                && lhs.elements == rhs.elements
                && lhs.noteShape == rhs.noteShape
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
    var noteShapeProvider: (() -> NoteShape)?
    var onNoteShapeRestored: ((NoteShape) -> Void)?
    /// Fired after an undo/redo snapshot restore. Selection must be invalidated:
    /// the programmatic drawing write suppresses onExternalDrawingChange, so
    /// stroke indices held by a selection would silently go stale.
    var onSnapshotApplied: (() -> Void)?

    private var isInTransaction = false
    private var activeTextSession: (elementID: UUID, baseline: [CanvasElement])?

    /// Opaque full-state token (drawing + elements + pages) captured at session start.
    struct LiveSessionToken {
        fileprivate let before: Snapshot
    }

    /// Elements are always fully materialized after hydrate.
    func hydrate(_ elements: [CanvasElement]) {
        self.elements = elements.zOrderMaterialized()
    }

    func cacheImage(_ image: UIImage, data: Data, forAssetPath assetPath: String) {
        imageCache[assetPath] = image
        imageDataCache[assetPath] = data
    }

    func addElement(_ element: CanvasElement) {
        performTransaction("Add \(kindName(for: element))") {
            elements.append(element)
            elements = elements.zOrderMaterialized()
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

    func beginTextEditingSession(for id: UUID) {
        if let activeTextSession, activeTextSession.elementID != id {
            finishTextEditingSession(matching: activeTextSession.elementID)
        }
        activeTextSession = (id, elements)
    }

    func finishTextEditingSession(matching id: UUID? = nil) {
        if let activeTextSession,
           id == nil || id == activeTextSession.elementID {
            let elementID = activeTextSession.elementID
            let baseline = activeTextSession.baseline
            self.activeTextSession = nil

            guard let element = elements.first(where: { $0.id == elementID }),
                  case .text(let content) = element.content else {
                return
            }

            let trimmed = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                removeElementLive(id: elementID)
                registerEditingSessionUndo(from: baseline, label: "Remove Text Box")
                return
            }

            let finalContent = TextBoxContent(
                text: trimmed,
                fontSize: content.fontSize,
                color: content.color
            )
            var updated = element
            updated.content = .text(finalContent)
            updated.frame.height = max(
                44,
                NotePageRenderer.growTextFrame(
                    updated.frame,
                    textContent: finalContent
                ).height
            )
            updateElementLive(updated)
            registerEditingSessionUndo(from: baseline, label: "Edit Text")
            return
        }

        guard let id,
              let element = elements.first(where: { $0.id == id }),
              case .text(let content) = element.content else {
            return
        }
        let trimmed = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            removeElement(id: id)
            return
        }

        let finalContent = TextBoxContent(
            text: trimmed,
            fontSize: content.fontSize,
            color: content.color
        )
        var updated = element
        updated.content = .text(finalContent)
        updated.frame.height = max(
            44,
            NotePageRenderer.growTextFrame(
                updated.frame,
                textContent: finalContent
            ).height
        )
        guard trimmed != content.text || updated.frame.height != element.frame.height else {
            return
        }
        updateElementLive(updated)
    }

    /// Begin a live session that may mutate BOTH the drawing and elements without
    /// registering undo. Pair with `commitLiveSession`.
    func beginLiveSession() -> LiveSessionToken {
        LiveSessionToken(before: snapshot())
    }

    /// Live drawing write (no undo registration). Must NOT be called inside performTransaction.
    /// Brackets the write with the coordinator's programmatic-change guards.
    func mutateDrawingLive(_ mutate: (inout PKDrawing) -> Void) {
        guard !isInTransaction else {
            assertionFailure("mutateDrawingLive must not be called inside performTransaction")
            return
        }
        guard let canvasView = canvasReference?.canvasView else { return }

        let coordinator = canvasReference?.coordinator
        coordinator?.beginProgrammaticChange()
        var drawing = canvasView.drawing
        mutate(&drawing)
        canvasView.drawing = drawing
        coordinator?.endProgrammaticChange(canvasView)
        onElementsChanged?(elements)
    }

    /// Append without undo registration; fires onElementsChanged.
    func addElementLive(_ element: CanvasElement) {
        elements.append(element)
        elements = elements.zOrderMaterialized()
        onElementsChanged?(elements)
    }

    /// Register exactly ONE undo step covering everything applied since the token was taken.
    /// No-op when nothing changed.
    func commitLiveSession(_ token: LiveSessionToken, label: String) {
        let after = snapshot()
        guard token.before != after else { return }
        guard let undoManager = undoManagerOverride ?? canvasReference?.canvasView?.undoManager else {
            return
        }
        registerUndo(
            on: undoManager,
            applying: token.before,
            inverse: after,
            label: label
        )
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
            noteShape: currentSnapshot.noteShape,
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
            noteShape: noteShapeProvider?(),
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
        if let noteShape = snapshot.noteShape {
            onNoteShapeRestored?(noteShape)
        }
        if let pages = snapshot.pages {
            onPagesRestored?(pages)
        }
        // Must run after onPagesRestored: editing-session undo snapshots capture current
        // pages with baseline elements, and this call re-syncs pages[0].elements last.
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
        case .shape:
            "Shape"
        case .unknown:
            "Object"
        }
    }
}
