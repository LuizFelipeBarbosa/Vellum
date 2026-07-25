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
    var onOperationFailed: ((String) -> Void)?
    /// Alignment lattice for a content-space point, or nil where there is nothing to align to.
    /// Supplied by the note screen, which is what knows the page background.
    var snapGrid: ((CGPoint) -> ShapeSnapGrid?)?

    private var captureStart: CGPoint?
    private var captureMode: SelectionMode?
    private var captureRect: CGRect?
    private var handleDragBounds: CGRect?
    private var drawingBeforeHide: PKDrawing?
    private var vertexDragBaseline: [CanvasElement]?
    private var vertexDragElementID: UUID?
    private var vertexDragIndex: Int?

    func beginCapture(at point: CGPoint, mode: SelectionMode) {
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
        restoreHiddenStrokes()
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

    func selectElement(id: UUID) {
        restoreHiddenStrokes()
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

    func beginMoveDrag() {
        guard let selection,
              let bounds = selectionBounds,
              bounds.width > 0,
              bounds.height > 0,
              let canvasView = canvasReference?.canvasView else {
            strokesSnapshot = nil
            return
        }

        resetHandleDrag()
        strokesSnapshot = snapshot(for: selection, in: bounds, canvasView: canvasView)
        hideSelectedStrokes()
        dragTranslation = .zero
    }

    func setDragTranslation(_ translation: CGSize) {
        dragTranslation = translation
    }

    func endMoveDrag() {
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
        return CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(
                CGAffineTransform(scaleX: handleScale.width, y: handleScale.height)
            )
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
        resetVertexDrag()

        guard let elementsStore,
              let element = elementsStore.elements.first(where: { $0.id == elementID }),
              case .shape = element.content else {
            return
        }

        vertexDragBaseline = elementsStore.elements
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

        switch shape.geometry {
        case .polyline:
            guard let moved = ShapeVertexEditor.movingVertex(
                at: vertexIndex,
                to: target,
                content: shape,
                frame: element.frame,
                rotation: element.rotation
            ) else {
                resetVertexDrag()
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
                resetVertexDrag()
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

    var canPaste: Bool {
        SelectionPasteboard.hasPayload
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

    func pasteFromPasteboard() async {
        guard let payload = SelectionPasteboard.read(),
              let drawing = try? PKDrawing(data: payload.drawingData),
              let elementsStore else { return }

        let duplicateOffset = CGSize(width: 20, height: 20)
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
                    rotation: element.rotation
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
                    rotation: element.rotation
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
                result = union(result, with: drawing.strokes[index].renderBounds)
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
                result = union(result, with: frame)
            }
        }

        return result
    }

    private func union(_ current: CGRect?, with candidate: CGRect) -> CGRect? {
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
