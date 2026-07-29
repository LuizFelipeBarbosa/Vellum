import Foundation
import Observation
import PencilKit
import SwiftUI
import UIKit
import VellumCore

@MainActor
@Observable
final class CanvasSelectionController {
    struct Selection {
        var strokeIndices: IndexSet
        var elementIDs: Set<UUID>
    }

    private(set) var selection: Selection?
    /// Content-space point where an empty-canvas tap asked for a paste affordance.
    /// Non-nil only while the bubble should be visible; mutually exclusive with `selection`.
    private(set) var pendingPasteTarget: CGPoint?
    private(set) var selectionBounds: CGRect?
    private(set) var capturePath: Path?
    private(set) var dragTranslation: CGSize = .zero
    private(set) var strokesSnapshot: UIImage?
    private(set) var handleScale = CGSize(width: 1, height: 1)
    private(set) var handleRotation: Double = 0
    private(set) var isHandleDragging = false
    private(set) var isVertexDragging = false
    weak var canvasReference: NoteCanvasReference?
    weak var elementsStore: CanvasElementsStore?
    var persistImageData: ((Data) async -> String?)?
    var importSystemImage: ((Data, CGPoint?) async -> UUID?)?
    var onOperationFailed: ((String) -> Void)?
    /// Alignment lattice for a content-space point, or nil where there is nothing to align to.
    /// Supplied by the note screen, which is what knows the page background.
    var snapGrid: ((CGPoint) -> ShapeSnapGrid?)?

    /// Only a lone element has one committed orientation the selection chrome can represent;
    /// strokes and multi-element selections keep the shared axis-aligned frame.
    var committedChromeRotation: Double {
        guard let selection,
              selection.strokeIndices.isEmpty,
              selection.elementIDs.count == 1,
              let elementID = selection.elementIDs.first,
              let element = elementsStore?.elements.first(where: { $0.id == elementID }) else {
            return 0
        }
        return element.rotation
    }

    private var captureStart: CGPoint?
    private var captureMode: SelectionMode?
    private var captureRect: CGRect?
    private var handleDragBounds: CGRect?
    private var drawingBeforeHide: PKDrawing?
    private var keepsSelectionThroughNextToolChange = false
    private var vertexDragBaseline: [CanvasElement]?
    private var vertexDragElementID: UUID?
    private var vertexDragIndex: Int?

    func beginCapture(at point: CGPoint, mode: SelectionMode) {
        dismissPasteAffordance()
        selection = nil
        selectionBounds = nil
        strokesSnapshot = nil
        dragTranslation = .zero
        resetHandleDrag()

        captureStart = point
        captureMode = mode
        captureRect = CGRect(origin: point, size: .zero)

        var path = Path()
        path.move(to: point)
        capturePath = path
    }

    func extendCapture(to point: CGPoint) {
        guard let captureStart, let captureMode else { return }

        switch captureMode {
        case .freeform:
            var path = capturePath ?? Path()
            path.addLine(to: point)
            capturePath = path
        case .boxed:
            let rect = CGRect(
                x: captureStart.x,
                y: captureStart.y,
                width: point.x - captureStart.x,
                height: point.y - captureStart.y
            ).standardized
            captureRect = rect
            capturePath = Path(rect)
        }
    }

    func endCapture() {
        guard let canvasView = canvasReference?.canvasView,
              let elementsStore,
              let captureMode else {
            finishCapture(with: nil)
            return
        }

        let selected: Selection
        switch captureMode {
        case .freeform:
            guard let path = capturePath else {
                finishCapture(with: nil)
                return
            }
            selected = Selection(
                strokeIndices: StrokeHitTester.strokeIndices(
                    in: canvasView.drawing,
                    containedBy: path.cgPath
                ),
                elementIDs: StrokeHitTester.elementIDs(
                    in: elementsStore.elements,
                    containedBy: path.cgPath
                )
            )
        case .boxed:
            guard let rect = captureRect else {
                finishCapture(with: nil)
                return
            }
            selected = Selection(
                strokeIndices: StrokeHitTester.strokeIndices(
                    in: canvasView.drawing,
                    intersecting: rect
                ),
                elementIDs: StrokeHitTester.elementIDs(
                    in: elementsStore.elements,
                    intersecting: rect
                )
            )
        }

        let hasSelection = !selected.strokeIndices.isEmpty || !selected.elementIDs.isEmpty
        finishCapture(with: hasSelection ? selected : nil)
    }

    func clearSelection() {
        dismissPasteAffordance()
        restoreHiddenStrokes()
        // The exemption below belongs to the selection a shape tap just made, so it dies with
        // that selection: an unrelated later tool change must never inherit it.
        keepsSelectionThroughNextToolChange = false
        selection = nil
        selectionBounds = nil
        capturePath = nil
        dragTranslation = .zero
        strokesSnapshot = nil
        resetHandleDrag()
        captureStart = nil
        captureMode = nil
        captureRect = nil
    }

    /// Selects one element. `survivesNextToolChange` is for selecting by tapping a shape, which
    /// also switches to the Select tool: without it the tool change would clear the selection the
    /// tap just made.
    func selectElement(id: UUID, survivesNextToolChange: Bool = false) {
        dismissPasteAffordance()
        restoreHiddenStrokes()
        keepsSelectionThroughNextToolChange = survivesNextToolChange
        let selection = Selection(
            strokeIndices: IndexSet(),
            elementIDs: [id]
        )
        self.selection = selection
        selectionBounds = bounds(for: selection)
        capturePath = nil
        dragTranslation = .zero
        strokesSnapshot = nil
        resetHandleDrag()
        captureStart = nil
        captureMode = nil
        captureRect = nil
    }

    /// Switching tools drops the selection, except the one a shape tap just made on its way into
    /// the Select tool.
    func toolChanged() {
        guard !keepsSelectionThroughNextToolChange else {
            keepsSelectionThroughNextToolChange = false
            dismissPasteAffordance()
            return
        }
        clearSelection()
    }

    /// True between `beginMoveDrag` and `endMoveDrag`. Derived rather than stored: the snapshot is
    /// exactly what a move puts up, and every path that drops a selection already clears it — a
    /// separate flag would be one more piece of state a torn-down drag could leave behind, and a
    /// stale one would lock handle drags out for good.
    private var isMoveDragging: Bool {
        strokesSnapshot != nil && !isHandleDragging
    }

    /// Takes the selection into a move drag. Returns false when it refuses the drag — there is
    /// nothing movable, or a handle drag already owns the selection — so a caller driving a pan
    /// can stop feeding translations into a move that never started.
    @discardableResult
    func beginMoveDrag() -> Bool {
        // A handle drag got here first, which means it has the selected strokes hidden and holds
        // the only copy of the drawing they came from. Hiding again would stash that already
        // trimmed drawing as the restore point and the hidden strokes would be lost for good, so
        // the drag in flight keeps the selection. The pinch path takes a move over legitimately
        // by ending it before it starts its handle drag.
        guard !isHandleDragging else { return false }

        guard let selection,
              let bounds = selectionBounds,
              bounds.width > 0,
              bounds.height > 0,
              let canvasView = canvasReference?.canvasView else {
            strokesSnapshot = nil
            return false
        }

        resetHandleDrag()
        strokesSnapshot = snapshot(for: selection, in: bounds, canvasView: canvasView)
        hideSelectedStrokes()
        dragTranslation = .zero
        return true
    }

    func setDragTranslation(_ translation: CGSize) {
        dragTranslation = translationSnappedToPageGrid(translation)
    }

    /// Pulls a dragged selection onto the page lattice once it carries a shape, so a shape lands
    /// on the paper the same way whether it was just drawn or moved here. Ink-only selections are
    /// left alone: freehand strokes have nothing to align.
    private func translationSnappedToPageGrid(_ translation: CGSize) -> CGSize {
        guard let anchor = selectedShapesAnchor() else { return translation }

        let dragged = CGPoint(
            x: anchor.x + translation.width,
            y: anchor.y + translation.height
        )
        guard let grid = snapGrid?(dragged) else { return translation }

        let snapped = ShapeGridSnapper.snappedPoint(dragged, to: grid)
        return CGSize(
            width: snapped.x - anchor.x,
            height: snapped.y - anchor.y
        )
    }

    /// Minimum corner of what the selected shapes actually draw, or nil when none are selected.
    /// Deliberately not `selectionBounds`: a line's frame is inflated to a minimum extent, so its
    /// box sits several points above the line and would snap the line off the rule.
    private func selectedShapesAnchor() -> CGPoint? {
        guard let selection, let elementsStore else { return nil }

        var drawn: CGRect?
        for element in elementsStore.elements
        where selection.elementIDs.contains(element.id) {
            guard case .shape(let content) = element.content else { continue }
            let box = ShapeGeometry.path(
                for: content,
                in: element.frame,
                rotation: element.rotation
            ).boundingBox
            guard !box.isNull, !box.isInfinite else { continue }
            drawn = drawn.map { $0.union(box) } ?? box
        }
        return drawn.map { CGPoint(x: $0.minX, y: $0.minY) }
    }

    func endMoveDrag() {
        // The mirror of the guard in `beginMoveDrag`: a handle drag owns the selection, and the
        // pan this refused must not restore its hidden strokes or commit a translation under it.
        guard !isHandleDragging else { return }

        restoreHiddenStrokes()
        guard let selection, let elementsStore else {
            strokesSnapshot = nil
            dragTranslation = .zero
            return
        }

        let translation = dragTranslation
        guard translation != .zero else {
            strokesSnapshot = nil
            dragTranslation = .zero
            return
        }

        elementsStore.performTransaction("Move Selection") {
            elementsStore.mutateDrawing { drawing in
                var strokes = drawing.strokes
                for index in selection.strokeIndices where strokes.indices.contains(index) {
                    strokes[index] = Self.copy(
                        strokes[index],
                        translatedBy: translation
                    )
                }
                drawing = PKDrawing(strokes: strokes)
            }

            for elementID in selection.elementIDs {
                guard var element = elementsStore.elements.first(where: { $0.id == elementID })
                else { continue }
                element.frame.x += Double(translation.width)
                element.frame.y += Double(translation.height)
                elementsStore.updateElement(element)
            }
        }

        self.selection = selection
        selectionBounds = bounds(for: selection)
        strokesSnapshot = nil
        dragTranslation = .zero
    }

    func beginHandleDrag() {
        // A move drag owns the selection until it ends, for the same reason a handle drag does:
        // the strokes are hidden and only the move holds the drawing they came from. `handlePinch`
        // promotes a move into a handle drag by ending the move first, which is exactly what makes
        // that takeover safe — anything arriving while the move is still in flight is ignored.
        guard !isMoveDragging else { return }

        guard let selection,
              let bounds = selectionBounds,
              bounds.width > 0,
              bounds.height > 0,
              let canvasView = canvasReference?.canvasView else {
            resetHandleDrag()
            strokesSnapshot = nil
            return
        }

        handleDragBounds = bounds
        handleScale = CGSize(width: 1, height: 1)
        handleRotation = 0
        isHandleDragging = true
        dragTranslation = .zero
        strokesSnapshot = snapshot(for: selection, in: bounds, canvasView: canvasView)
        hideSelectedStrokes()
    }

    func setHandleTransform(scale: CGSize, rotation: Double) {
        guard isHandleDragging else { return }
        handleScale = scale
        handleRotation = rotation
    }

    func endHandleDrag() {
        // No handle drag is in flight: either it was refused because a move owns the selection, or
        // something already tore it down. Going further would restore strokes and drop a snapshot
        // that now belong to whoever does own it.
        guard isHandleDragging else { return }

        restoreHiddenStrokes()
        guard let selection,
              let elementsStore,
              let dragBounds = handleDragBounds else {
            strokesSnapshot = nil
            resetHandleDrag()
            return
        }

        let scale = clampedScale(handleScale, for: dragBounds)
        let rotation = handleRotation
        guard scale != CGSize(width: 1, height: 1) || rotation != 0 else {
            strokesSnapshot = nil
            resetHandleDrag()
            return
        }

        let center = CGPoint(x: dragBounds.midX, y: dragBounds.midY)
        // CGAffineTransform uses row-vector concatenation: p * T(-c) * S * R * T(c).
        // Applying these operations in this order first moves c to zero and finally restores it,
        // so the selection center is invariant under the scale-and-rotation composite.
        let composite = CGAffineTransform(
            translationX: -center.x,
            y: -center.y
        )
        .concatenating(
            CGAffineTransform(scaleX: scale.width, y: scale.height)
        )
        .concatenating(CGAffineTransform(rotationAngle: rotation))
        .concatenating(
            CGAffineTransform(translationX: center.x, y: center.y)
        )

        elementsStore.performTransaction("Transform Selection") {
            elementsStore.mutateDrawing { drawing in
                var strokes = drawing.strokes
                for index in selection.strokeIndices where strokes.indices.contains(index) {
                    strokes[index] = Self.copy(strokes[index], applying: composite)
                }
                drawing = PKDrawing(strokes: strokes)
            }

            for elementID in selection.elementIDs {
                guard var element = elementsStore.elements.first(where: { $0.id == elementID })
                else { continue }

                let oldCenter = CGPoint(
                    x: element.frame.x + element.frame.width / 2,
                    y: element.frame.y + element.frame.height / 2
                )
                let transformedCenter = oldCenter.applying(composite)
                element.frame.width *= Double(scale.width)
                element.frame.height *= Double(scale.height)
                element.frame.x = Double(transformedCenter.x) - element.frame.width / 2
                element.frame.y = Double(transformedCenter.y) - element.frame.height / 2
                element.rotation += rotation

                if case .text(var text) = element.content {
                    text.fontSize *= Double(min(scale.width, scale.height))
                    element.content = .text(text)
                } else if case .shape(var shape) = element.content {
                    shape.strokeWidth *= Double(min(scale.width, scale.height))
                    element.content = .shape(shape)
                }
                elementsStore.updateElement(element)
            }
        }

        self.selection = selection
        selectionBounds = bounds(for: selection)
        strokesSnapshot = nil
        resetHandleDrag()
    }

    /// Content-space preview transform for an element while a selection drag is in flight, so
    /// element layers follow the selection box instead of sitting still until the drop. Selected
    /// strokes get the same preview from `strokesSnapshot`; elements need no snapshot because
    /// their layer can simply be transformed in place. Identity for anything not being dragged.
    func liveTransform(forElementWith id: UUID) -> CGAffineTransform {
        guard let selection, selection.elementIDs.contains(id) else { return .identity }

        guard isHandleDragging else {
            return CGAffineTransform(
                translationX: dragTranslation.width,
                y: dragTranslation.height
            )
        }
        guard let bounds = selectionBounds else { return .identity }

        // Same composition as endHandleDrag, using the raw handle scale so the preview matches
        // the stroke snapshot; endHandleDrag clamps only when it commits.
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let scale = CGAffineTransform(
            scaleX: handleScale.width,
            y: handleScale.height
        )
        let committedRotation = committedChromeRotation
        let previewScale: CGAffineTransform
        if committedRotation != 0 {
            // The element paints in its own rotated axes, so an asymmetric live resize must use
            // those axes too or its preview will disagree with the locally sized commit.
            previewScale = CGAffineTransform(rotationAngle: -committedRotation)
                .concatenating(scale)
                .concatenating(CGAffineTransform(rotationAngle: committedRotation))
        } else {
            previewScale = scale
        }

        return CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(previewScale)
            .concatenating(CGAffineTransform(rotationAngle: handleRotation))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }

    /// The single selected `.shape` polyline element eligible for vertex editing, or nil.
    /// Requires exactly one selected element, zero selected strokes, and polyline geometry.
    func vertexEditableElement() -> CanvasElement? {
        guard let selection,
              selection.strokeIndices.isEmpty,
              selection.elementIDs.count == 1,
              let elementID = selection.elementIDs.first,
              let element = elementsStore?.elements.first(where: { $0.id == elementID }),
              case .shape = element.content else {
            return nil
        }
        return element
    }

    /// Where the on-shape edit handles belong, in content space: one per vertex for a polyline,
    /// one per axis end for an ellipse — which has no vertices to grab but is still draggable
    /// by its own curve rather than by a box around it.
    func vertexEditHandles(for element: CanvasElement) -> [CGPoint] {
        guard case .shape(let shape) = element.content else { return [] }

        switch shape.geometry {
        case .polyline:
            return ShapeVertexEditor.absoluteVertices(
                content: shape,
                frame: element.frame,
                rotation: element.rotation
            )
        case .ellipse:
            return ShapeEllipseEditor.radiusHandles(
                frame: element.frame,
                rotation: element.rotation
            )
        }
    }

    func beginVertexDrag(elementID: UUID, vertexIndex: Int) {
        guard let elementsStore,
              let element = elementsStore.elements.first(where: { $0.id == elementID }),
              case .shape = element.content else {
            resetVertexDrag()
            return
        }

        // Ownership of a two-finger vertex drag alternates between the handles, and every takeover
        // arrives here. Re-snapshotting would take the baseline from elements this same gesture has
        // already moved, leaving everything before the last takeover outside "Edit Shape"; holding
        // the pre-edit snapshot until `endVertexDrag` clears it keeps the whole gesture undoable as
        // one step. A takeover therefore only retargets which vertex the samples move.
        if vertexDragBaseline == nil {
            vertexDragBaseline = elementsStore.elements
        }
        vertexDragElementID = elementID
        vertexDragIndex = vertexIndex
        isVertexDragging = true
    }

    func setVertexPosition(_ contentPoint: CGPoint) {
        guard isVertexDragging else { return }
        guard let elementID = vertexDragElementID,
              let vertexIndex = vertexDragIndex,
              let elementsStore else {
            resetVertexDrag()
            return
        }
        // The element the drag started on is gone or is no longer a shape, so something outside
        // this gesture rewrote the store. The baseline predates that rewrite and would fold it
        // into "Edit Shape", so this session is abandoned rather than finished.
        guard var element = elementsStore.elements.first(where: { $0.id == elementID }),
              case .shape(let shape) = element.content else {
            resetVertexDrag()
            return
        }

        // Editing lands on the paper's lattice for the same reason drawing does.
        let target = ShapeGridSnapper.snappedPoint(
            contentPoint,
            to: snapGrid?(contentPoint)
        )

        // A sample the editors can't convert is dropped, not fatal to the drag: earlier samples
        // were already applied live, so tearing the session down here would strand them with no
        // baseline and leave the reshaped element non-undoable.
        switch shape.geometry {
        case .polyline:
            guard let moved = ShapeVertexEditor.movingVertex(
                at: vertexIndex,
                to: target,
                content: shape,
                frame: element.frame,
                rotation: element.rotation
            ) else {
                return
            }
            element.content = .shape(moved.content)
            element.frame = moved.frame
        case .ellipse:
            guard let resized = ShapeEllipseEditor.resizing(
                handleIndex: vertexIndex,
                to: target,
                frame: element.frame,
                rotation: element.rotation
            ) else {
                return
            }
            element.frame = resized
        }
        elementsStore.updateElementLive(element)

        if let selection = self.selection {
            self.selection = selection
            selectionBounds = bounds(for: selection)
        }
    }

    func endVertexDrag() {
        defer { resetVertexDrag() }
        guard isVertexDragging,
              let vertexDragBaseline,
              let elementsStore else {
            return
        }
        elementsStore.registerEditingSessionUndo(
            from: vertexDragBaseline,
            label: "Edit Shape"
        )
    }

    /// True when `restyleSelection` would actually touch something in the current selection:
    /// strokes, or elements whose content is `.shape` or `.text`. False for no selection, or a
    /// selection made only of `.image` / `.unknown` elements (restyleSelection skips those).
    var selectionSupportsStyling: Bool {
        guard let selection else { return false }
        if !selection.strokeIndices.isEmpty { return true }
        guard let elementsStore else { return false }
        return selection.elementIDs.contains { id in
            guard let element = elementsStore.elements.first(where: { $0.id == id }) else {
                return false
            }
            switch element.content {
            case .shape, .text: return true
            case .image, .unknown: return false
            }
        }
    }

    func restyleSelection(color: CodableColor?, strokeWidth: Double?) {
        guard let selection, let elementsStore else { return }

        elementsStore.performTransaction("Restyle Selection") {
            elementsStore.mutateDrawing { drawing in
                var strokes = drawing.strokes
                for index in selection.strokeIndices where strokes.indices.contains(index) {
                    let stroke = strokes[index]
                    let ink = color.map {
                        PKInk(stroke.ink.inkType, color: $0.uiColor)
                    } ?? stroke.ink
                    var path = stroke.path

                    if let strokeWidth,
                       strokeWidth > 0,
                       let currentWidth = Self.currentAverageTipWidth(stroke),
                       currentWidth > 0 {
                        let factor = CGFloat(strokeWidth / currentWidth)
                        let points = stroke.path.map { point in
                            Self.copy(point, scalingTipBy: factor)
                        }
                        // Rebuilding the path can shift random-seeded pencil/crayon textures
                        // slightly; preserving the seed still makes that accepted and expected.
                        path = PKStrokePath(
                            controlPoints: points,
                            creationDate: stroke.path.creationDate
                        )
                    }

                    strokes[index] = PKStroke(
                        ink: ink,
                        path: path,
                        transform: stroke.transform,
                        mask: stroke.mask,
                        randomSeed: stroke.randomSeed
                    )
                }
                drawing = PKDrawing(strokes: strokes)
            }

            if color != nil || strokeWidth != nil {
                for elementID in selection.elementIDs {
                    guard var element = elementsStore.elements.first(
                        where: { $0.id == elementID }
                    ) else { continue }

                    var didChange = false
                    switch element.content {
                    case .text(var text):
                        if let color, text.color != color {
                            text.color = color
                            element.content = .text(text)
                            didChange = true
                        }
                    case .shape(var shape):
                        if let color, shape.strokeColor != color {
                            shape.strokeColor = color
                            didChange = true
                        }
                        if let strokeWidth,
                           strokeWidth > 0,
                           shape.strokeWidth != strokeWidth {
                            shape.strokeWidth = strokeWidth
                            didChange = true
                        }
                        if didChange {
                            element.content = .shape(shape)
                        }
                    case .image, .unknown:
                        continue
                    }

                    if didChange {
                        elementsStore.updateElement(element)
                    }
                }
            }
        }

        self.selection = selection
        selectionBounds = bounds(for: selection)
    }

    func flipSelection(horizontal: Bool) {
        guard let selection,
              let elementsStore,
              let flipBounds = selectionBounds,
              !isHandleDragging,
              !isVertexDragging,
              !isMoveDragging else {
            return
        }

        let pivot = CGPoint(x: flipBounds.midX, y: flipBounds.midY)
        let reflection = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(
                CGAffineTransform(
                    scaleX: horizontal ? -1 : 1,
                    y: horizontal ? 1 : -1
                )
            )
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))

        elementsStore.performTransaction(horizontal ? "Flip Horizontal" : "Flip Vertical") {
            elementsStore.mutateDrawing { drawing in
                var strokes = drawing.strokes
                for index in selection.strokeIndices where strokes.indices.contains(index) {
                    strokes[index] = Self.flippedStroke(strokes[index], applying: reflection)
                }
                drawing = PKDrawing(strokes: strokes)
            }

            for elementID in selection.elementIDs {
                guard let element = elementsStore.elements.first(where: { $0.id == elementID })
                else { continue }
                elementsStore.updateElement(
                    element.flipped(horizontal: horizontal, aboutPivot: pivot)
                )
            }
        }

        self.selection = selection
        selectionBounds = bounds(for: selection)
    }

    var canReorderSelection: Bool {
        guard let selection else { return false }
        return selection.strokeIndices.isEmpty && !selection.elementIDs.isEmpty
    }

    func reorderSelection(_ direction: ReorderDirection) {
        guard canReorderSelection,
              !isHandleDragging,
              !isVertexDragging,
              !isMoveDragging else {
            return
        }

        let inkRects =
            canvasReference?.canvasView?.drawing.strokes.map(\.renderBounds) ?? []
        guard let selection, let elementsStore else { return }
        guard let reordered = ElementReorderer.reorder(
            elements: elementsStore.elements,
            selectedIDs: selection.elementIDs,
            direction: direction,
            inkRects: inkRects
        ) else {
            return
        }

        elementsStore.performTransaction(direction.undoLabel) {
            elementsStore.replaceAllElements(reordered)
        }
    }

    var canPaste: Bool {
        SelectionPasteboard.hasPayload || SelectionPasteboard.hasSystemImage
    }

    func requestPasteAffordance(at point: CGPoint) {
        guard canPaste else {
            pendingPasteTarget = nil
            return
        }
        pendingPasteTarget = point
    }

    func dismissPasteAffordance() {
        pendingPasteTarget = nil
    }

    @discardableResult
    func copySelection() -> Bool {
        guard let selection,
              let canvasView = canvasReference?.canvasView,
              let elementsStore else { return false }

        let strokes = selection.strokeIndices.compactMap { index in
            canvasView.drawing.strokes.indices.contains(index)
                ? canvasView.drawing.strokes[index]
                : nil
        }
        let elements = elementsStore.elements.filter {
            selection.elementIDs.contains($0.id)
        }
        var imageAssets: [String: Data] = [:]
        for element in elements {
            guard case .image(let image) = element.content else { continue }
            guard let data = elementsStore.imageDataCache[image.assetPath] else {
                return false
            }
            imageAssets[image.assetPath] = data
        }

        return SelectionPasteboard.write(
            SelectionPasteboardPayload(
                drawingData: PKDrawing(strokes: strokes).dataRepresentation(),
                elements: elements,
                imageAssets: imageAssets
            )
        )
    }

    func cutSelection() {
        guard copySelection() else {
            onOperationFailed?("Couldn't cut: image data still loading")
            return
        }
        deleteSelection()
    }

    func pasteFromPasteboard(at target: CGPoint? = nil) async {
        dismissPasteAffordance()
        guard let payload = SelectionPasteboard.read() else {
            guard SelectionPasteboard.hasSystemImage,
                  let data = SelectionPasteboard.readSystemImageData(),
                  let importedID = await importSystemImage?(data, target) else { return }
            selectElement(id: importedID)
            return
        }
        guard let drawing = try? PKDrawing(data: payload.drawingData),
              let elementsStore else { return }

        let duplicateOffset: CGSize
        if let target {
            duplicateOffset = Self.pasteOffset(
                forTarget: target,
                drawing: drawing,
                elements: payload.elements
            )
        } else {
            duplicateOffset = CGSize(width: 20, height: 20)
        }
        let pastedStrokes = drawing.strokes.map {
            Self.copy($0, translatedBy: duplicateOffset)
        }
        var pastedElements: [CanvasElement] = []
        var imagesToCache: [(image: UIImage, data: Data, assetPath: String)] = []

        for element in payload.elements {
            var content = element.content
            if case .image(var imageContent) = content {
                guard let bytes = payload.imageAssets[imageContent.assetPath],
                      let image = UIImage(data: bytes),
                      let persistImageData,
                      let newAssetPath = await persistImageData(bytes) else { continue }
                imageContent.assetPath = newAssetPath
                content = .image(imageContent)
                imagesToCache.append((image, bytes, newAssetPath))
            }

            var frame = element.frame
            frame.x += Double(duplicateOffset.width)
            frame.y += Double(duplicateOffset.height)
            pastedElements.append(
                CanvasElement(
                    content: content,
                    frame: frame,
                    rotation: element.rotation,
                    layerPlacement: element.layerPlacement
                )
            )
        }

        guard !pastedStrokes.isEmpty || !pastedElements.isEmpty else { return }

        var pastedStrokeIndices = IndexSet()
        elementsStore.performTransaction("Paste Selection") {
            elementsStore.mutateDrawing { drawing in
                let firstPastedIndex = drawing.strokes.count
                drawing.strokes.append(contentsOf: pastedStrokes)
                pastedStrokeIndices = IndexSet(
                    integersIn: firstPastedIndex..<drawing.strokes.count
                )
            }

            for cachedImage in imagesToCache {
                elementsStore.cacheImage(
                    cachedImage.image,
                    data: cachedImage.data,
                    forAssetPath: cachedImage.assetPath
                )
            }
            for element in pastedElements {
                elementsStore.addElement(element)
            }
        }

        let pastedSelection = Selection(
            strokeIndices: pastedStrokeIndices,
            elementIDs: Set(pastedElements.map(\.id))
        )
        self.selection = pastedSelection
        selectionBounds = bounds(for: pastedSelection)
        capturePath = nil
        strokesSnapshot = nil
        dragTranslation = .zero
        resetHandleDrag()
    }

    func deleteSelection() {
        guard let selection, let elementsStore else {
            clearSelection()
            return
        }

        elementsStore.performTransaction("Delete Selection") {
            elementsStore.mutateDrawing { drawing in
                var strokes = drawing.strokes
                for index in selection.strokeIndices.sorted(by: >)
                    where strokes.indices.contains(index) {
                    strokes.remove(at: index)
                }
                drawing = PKDrawing(strokes: strokes)
            }

            for elementID in selection.elementIDs {
                elementsStore.removeElement(id: elementID)
            }
        }

        clearSelection()
    }

    func duplicateSelection() {
        guard let selection, let elementsStore else { return }

        let duplicateOffset = CGSize(width: 20, height: 20)
        var duplicatedStrokeIndices = IndexSet()
        var duplicatedElementIDs = Set<UUID>()

        elementsStore.performTransaction("Duplicate Selection") {
            elementsStore.mutateDrawing { drawing in
                let selectedStrokes = selection.strokeIndices.compactMap { index in
                    drawing.strokes.indices.contains(index) ? drawing.strokes[index] : nil
                }
                let firstDuplicateIndex = drawing.strokes.count
                drawing.strokes.append(
                    contentsOf: selectedStrokes.map {
                        Self.copy($0, translatedBy: duplicateOffset)
                    }
                )
                duplicatedStrokeIndices = IndexSet(
                    integersIn: firstDuplicateIndex..<drawing.strokes.count
                )
            }

            for elementID in selection.elementIDs {
                guard let element = elementsStore.elements.first(where: { $0.id == elementID })
                else { continue }
                var frame = element.frame
                frame.x += Double(duplicateOffset.width)
                frame.y += Double(duplicateOffset.height)
                let duplicate = CanvasElement(
                    content: element.content,
                    frame: frame,
                    rotation: element.rotation,
                    layerPlacement: element.layerPlacement
                )
                duplicatedElementIDs.insert(duplicate.id)
                elementsStore.addElement(duplicate)
            }
        }

        let duplicatedSelection = Selection(
            strokeIndices: duplicatedStrokeIndices,
            elementIDs: duplicatedElementIDs
        )
        if duplicatedStrokeIndices.isEmpty, duplicatedElementIDs.isEmpty {
            clearSelection()
        } else {
            self.selection = duplicatedSelection
            selectionBounds = bounds(for: duplicatedSelection)
            capturePath = nil
            strokesSnapshot = nil
            dragTranslation = .zero
            resetHandleDrag()
        }
    }

    func externalDrawingDidChange() {
        // Undo, redo, or external snapshot application has already replaced the drawing;
        // restoring the stale pre-hide drawing here would overwrite that new truth.
        drawingBeforeHide = nil
        canvasReference?.coordinator?.hasTransientDrawingOverride = false
        clearSelection()
    }

    private func finishCapture(with selection: Selection?) {
        self.selection = selection
        selectionBounds = selection.flatMap(bounds(for:))
        capturePath = nil
        captureStart = nil
        captureMode = nil
        captureRect = nil
    }

    private func bounds(for selection: Selection) -> CGRect? {
        var result: CGRect?

        if let drawing = canvasReference?.canvasView?.drawing {
            for index in selection.strokeIndices where drawing.strokes.indices.contains(index) {
                // PencilKit's renderBounds is already in drawing space, including stroke.transform.
                result = Self.union(result, with: drawing.strokes[index].renderBounds)
            }
        }

        if let elementsStore {
            for element in elementsStore.elements where selection.elementIDs.contains(element.id) {
                let frame = CGRect(
                    x: element.frame.x,
                    y: element.frame.y,
                    width: element.frame.width,
                    height: element.frame.height
                ).standardized
                result = Self.union(result, with: frame)
            }
        }

        return result
    }

    /// Content-space rect the action strip must keep clear of: the selection's handle chrome
    /// plus the painted extent of rotated elements. `selectionBounds` itself still drives the
    /// outline and handles.
    var stripAvoidanceBounds: CGRect? {
        guard let selection, let selectionBounds else { return nil }
        var result = selectionBounds.insetBy(
            dx: -SelectionHandleGeometry.resizeHitSize / 2,
            dy: -SelectionHandleGeometry.resizeHitSize / 2
        )                                                               // resize-handle chrome
        result = result.union(CGRect(                                    // rotation handle band
            x: selectionBounds.midX - SelectionHandleGeometry.rotationHitSize / 2,
            y: selectionBounds.minY - (
                SelectionHandleGeometry.rotationOffset
                    + SelectionHandleGeometry.rotationHitSize / 2
            ),
            width: SelectionHandleGeometry.rotationHitSize,
            height: SelectionHandleGeometry.rotationOffset
                + SelectionHandleGeometry.rotationHitSize / 2
        ))
        if let elementsStore {
            for element in elementsStore.elements
            where selection.elementIDs.contains(element.id) && element.rotation != 0 {
                result = result.union(element.rotatedBoundingBox)
            }
        }
        return result
    }

    private static func union(_ current: CGRect?, with candidate: CGRect) -> CGRect? {
        guard !candidate.isNull, !candidate.isInfinite else { return current }
        return current?.union(candidate) ?? candidate
    }

    private func snapshot(
        for selection: Selection,
        in bounds: CGRect,
        canvasView: PKCanvasView
    ) -> UIImage {
        let strokes = selection.strokeIndices.compactMap { index in
            canvasView.drawing.strokes.indices.contains(index)
                ? canvasView.drawing.strokes[index]
                : nil
        }
        let scale = canvasView.window?.screen.scale ?? 2
        return PKDrawing(strokes: strokes).image(from: bounds, scale: scale)
    }

    private func hideSelectedStrokes() {
        // `drawingBeforeHide` is the only copy of the drawing the hidden strokes still live in, so
        // whoever hid first keeps it until it restores. Overwriting it with the already trimmed
        // drawing would delete the selected indices a second time — from a drawing where those
        // indices now address other strokes — and neither the canvas nor the undo baseline the
        // following commit takes would still contain the originals. The drags guard each other at
        // their entry points; this is the backstop that makes every other route survivable too.
        guard drawingBeforeHide == nil else { return }

        guard let selection,
              !selection.strokeIndices.isEmpty,
              let canvasView = canvasReference?.canvasView else { return }

        drawingBeforeHide = canvasView.drawing
        var strokes = canvasView.drawing.strokes
        for index in selection.strokeIndices.sorted(by: >)
            where strokes.indices.contains(index) {
            strokes.remove(at: index)
        }

        // This transient hide must not trigger autosave, undo, or external-change notifications.
        canvasReference?.coordinator?.hasTransientDrawingOverride = true
        if let coordinator = canvasReference?.coordinator {
            coordinator.performSilentChange {
                canvasView.drawing = PKDrawing(strokes: strokes)
            }
        } else {
            canvasView.drawing = PKDrawing(strokes: strokes)
        }
    }

    private func restoreHiddenStrokes() {
        let drawing = drawingBeforeHide
        defer {
            drawingBeforeHide = nil
            canvasReference?.coordinator?.hasTransientDrawingOverride = false
        }
        guard let drawing,
              let canvasView = canvasReference?.canvasView else { return }

        if let coordinator = canvasReference?.coordinator {
            coordinator.performSilentChange {
                canvasView.drawing = drawing
            }
        } else {
            canvasView.drawing = drawing
        }
    }

    private func clampedScale(_ scale: CGSize, for bounds: CGRect) -> CGSize {
        let minimumWidthScale = 12 / bounds.width
        let minimumHeightScale = 12 / bounds.height
        let width = scale.width.isFinite ? scale.width : 1
        let height = scale.height.isFinite ? scale.height : 1
        return CGSize(
            width: max(width, minimumWidthScale),
            height: max(height, minimumHeightScale)
        )
    }

    private func resetHandleDrag() {
        handleScale = CGSize(width: 1, height: 1)
        handleRotation = 0
        isHandleDragging = false
        handleDragBounds = nil
    }

    private func resetVertexDrag() {
        isVertexDragging = false
        vertexDragBaseline = nil
        vertexDragElementID = nil
        vertexDragIndex = nil
    }

    private static func pasteOffset(
        forTarget target: CGPoint,
        drawing: PKDrawing,
        elements: [CanvasElement]
    ) -> CGSize {
        var payloadBounds: CGRect?
        if !drawing.strokes.isEmpty {
            payloadBounds = Self.union(payloadBounds, with: drawing.bounds)
        }
        for element in elements {
            payloadBounds = Self.union(payloadBounds, with: element.rotatedBoundingBox)
        }

        guard let payloadBounds else {
            return CGSize(width: 20, height: 20)
        }

        var delta = CGSize(
            width: target.x - payloadBounds.midX,
            height: target.y - payloadBounds.midY
        )

        // X protects both finite page edges when the payload fits; Y protects only the top because pages grow downward without a bottom edge.
        if payloadBounds.width <= PageLayout.contentWidth {
            let translatedMinX = payloadBounds.minX + delta.width
            let translatedMaxX = payloadBounds.maxX + delta.width
            if translatedMinX < 0 {
                delta.width -= translatedMinX
            } else if translatedMaxX > PageLayout.contentWidth {
                delta.width -= translatedMaxX - PageLayout.contentWidth
            }
        }

        let translatedMinY = payloadBounds.minY + delta.height
        if translatedMinY < 0 {
            delta.height -= translatedMinY
        }
        return delta
    }

    private static func copy(_ stroke: PKStroke, translatedBy translation: CGSize) -> PKStroke {
        PKStroke(
            ink: stroke.ink,
            path: stroke.path,
            transform: stroke.transform.concatenating(
                CGAffineTransform(
                    translationX: translation.width,
                    y: translation.height
                )
            ),
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
        )
    }

    private static func copy(_ stroke: PKStroke, applying transform: CGAffineTransform) -> PKStroke {
        PKStroke(
            ink: stroke.ink,
            path: stroke.path,
            transform: stroke.transform.concatenating(transform),
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
        )
    }

    private static func flippedStroke(
        _ stroke: PKStroke,
        applying reflection: CGAffineTransform
    ) -> PKStroke {
        // FALLBACK: If PencilKit rejects or normalizes negative-determinant transforms, rebuild
        // stroke.path as in restyleSelection, applying the same reflection directly to each
        // PKStrokePoint location, and drop the transform-based approach. The rest can stay put.
        Self.copy(stroke, applying: reflection)
    }

    private static func currentAverageTipWidth(_ stroke: PKStroke) -> Double? {
        guard !stroke.path.isEmpty else { return nil }
        let total = stroke.path.reduce(CGFloat.zero) { partial, point in
            partial + point.size.width
        }
        return Double(total / CGFloat(stroke.path.count))
    }

    private static func copy(
        _ point: PKStrokePoint,
        scalingTipBy factor: CGFloat
    ) -> PKStrokePoint {
        let size = CGSize(
            width: point.size.width * factor,
            height: point.size.height * factor
        )
        if #available(iOS 26.0, *) {
            return PKStrokePoint(
                location: point.location,
                timeOffset: point.timeOffset,
                size: size,
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude,
                secondaryScale: point.secondaryScale,
                threshold: point.threshold
            )
        }
        return PKStrokePoint(
            location: point.location,
            timeOffset: point.timeOffset,
            size: size,
            opacity: point.opacity,
            force: point.force,
            azimuth: point.azimuth,
            altitude: point.altitude,
            secondaryScale: point.secondaryScale
        )
    }
}
