import Foundation
import Observation
import PencilKit
import UIKit
import VellumCore

enum ShapeSnapPolicy {
    case snapMidStroke
    case snapOnLift

    /// The UserDefaults key doubles as a release-build kill switch: mid-stroke
    /// snapping relies on undocumented PencilKit cancel semantics, so an OS
    /// update that breaks it must be recoverable without shipping a hotfix.
    static let snapOnLiftDefaultsKey = "vellum.shapeSnapOnLift"

    static func resolveFromLaunchArguments() -> ShapeSnapPolicy {
        if ProcessInfo.processInfo.arguments.contains("-vellum-shape-snap-on-lift")
            || UserDefaults.standard.bool(forKey: snapOnLiftDefaultsKey) {
            return .snapOnLift
        }
        return .snapMidStroke
    }
}

@MainActor
@Observable
final class ShapeSnapController {
    weak var canvasReference: NoteCanvasReference?
    weak var elementsStore: CanvasElementsStore?
    var isEnabled = false
    var activeInkConfig: InkToolConfig?
    var isDrawingEnabled = true
    let policy: ShapeSnapPolicy

    var detector = DwellDetector()
    var capturedContentPoints: [CGPoint] = []
    var pendingDwellWorkItem: DispatchWorkItem?
    var isTrackingStroke = false
    var hasSnappedThisStroke = false
    var pendingShapeToCommitOnLift: RecognizedShape?
    var pendingCaptureBoundingBox: CGRect?

    private struct LineAdjustState {
        let elementID: UUID
        let pivot: CGPoint
        let strokeColor: CodableColor
        let strokeWidth: Double
        let liveSessionToken: CanvasElementsStore.LiveSessionToken
        var isAxisSnapped: Bool
    }

    private var lineAdjustState: LineAdjustState?
    private var dwellScheduleGeneration = 0
    private static let capturePointLimit = 4_096
    private static let captureBoundsInflation: CGFloat = 20

    init(policy: ShapeSnapPolicy = ShapeSnapPolicy.resolveFromLaunchArguments()) {
        self.policy = policy
    }

    func strokeBegan() {
        guard isEnabled else { return }

        detector.reset()
        capturedContentPoints.removeAll(keepingCapacity: true)
        cancelPendingDwell()
        isTrackingStroke = true
        hasSnappedThisStroke = false
        pendingShapeToCommitOnLift = nil
        pendingCaptureBoundingBox = nil
    }

    func strokeContinued(points: [TimedPoint]) {
        guard isEnabled,
              isTrackingStroke,
              let canvasView = canvasReference?.canvasView,
              canvasView.zoomScale > 0 else {
            return
        }

        let zoomScale = canvasView.zoomScale
        if var lineAdjustState {
            // SwiftUI updates can re-enable this recognizer after each observable
            // element mutation. Re-assert the live-adjustment invariant for every sample.
            canvasView.drawingGestureRecognizer.isEnabled = false
            guard let latestPoint = points.last else { return }

            let rawPoint = CGPoint(
                x: latestPoint.location.x / zoomScale,
                y: latestPoint.location.y / zoomScale
            )
            let adjusted = ShapeLineAdjuster.adjustedEndpoint(
                pivot: lineAdjustState.pivot,
                rawPoint: rawPoint
            )
            let enteredAxisSnap = !lineAdjustState.isAxisSnapped
                && adjusted.isAxisSnapped
            lineAdjustState.isAxisSnapped = adjusted.isAxisSnapped
            self.lineAdjustState = lineAdjustState

            guard let elementsStore,
                  let existingElement = elementsStore.elements.first(where: {
                      $0.id == lineAdjustState.elementID
                  }) else {
                return
            }
            let builtElement = ShapeElementBuilder.element(
                from: .polyline(
                    vertices: [lineAdjustState.pivot, adjusted.point],
                    isClosed: false
                ),
                strokeColor: lineAdjustState.strokeColor,
                strokeWidth: lineAdjustState.strokeWidth
            )
            elementsStore.updateElementLive(
                CanvasElement(
                    id: existingElement.id,
                    content: .shape(builtElement.content),
                    frame: builtElement.frame,
                    rotation: builtElement.rotation,
                    createdAt: existingElement.createdAt
                )
            )
            if enteredAxisSnap {
                (canvasView as? PagedCanvasView)?.haptics.playSnapToFit()
            }
            return
        }

        guard !hasSnappedThisStroke else { return }

        var contentPoints: [CGPoint] = []
        contentPoints.reserveCapacity(points.count)
        for point in points {
            let contentPoint = CGPoint(
                x: point.location.x / zoomScale,
                y: point.location.y / zoomScale
            )
            contentPoints.append(contentPoint)
            detector.ingest(contentPoint, at: point.timestamp)
        }

        capturedContentPoints.append(contentsOf: contentPoints)
        let excessPointCount = capturedContentPoints.count - Self.capturePointLimit
        if excessPointCount > 0 {
            capturedContentPoints.removeFirst(excessPointCount)
        }

        guard let stationarySince = detector.stationarySince else {
            cancelPendingDwell()
            return
        }
        guard let lastSampleTimestamp = points.last?.timestamp,
              lastSampleTimestamp.isFinite else {
            cancelPendingDwell()
            return
        }

        let delay = max(
            0,
            stationarySince + detector.config.holdDuration - lastSampleTimestamp
        )
        scheduleDwell(after: delay)
    }

    func dwellFired() {
        guard isEnabled,
              isTrackingStroke,
              let canvasView = canvasReference?.canvasView,
              !canvasView.isZooming,
              (canvasView as? PagedCanvasView)?.isAnimatingZoomSnap != true,
              capturedContentPoints.count >= 2 else {
            return
        }

        let shape = ShapeRecognizer.recognize(points: capturedContentPoints)
        cancelPendingDwell()
        detector.reset()
        guard let shape else { return }

        switch policy {
        case .snapMidStroke:
            performMidStrokeSnap(shape: shape)
        case .snapOnLift:
            pendingShapeToCommitOnLift = shape
            pendingCaptureBoundingBox = captureBoundingBox()
            (canvasView as? PagedCanvasView)?.haptics.playSnapToFit()
        }
    }

    func performMidStrokeSnap(shape: RecognizedShape) {
        // Resolve every input the async commit needs BEFORE disabling the
        // PencilKit recognizer. If the pen lifts while the commit is queued
        // on the next runloop turn, `strokeEnded` -> `resetStrokeState()`
        // clears `capturedContentPoints` (and a tool switch can clear
        // `activeInkConfig`); reading those lazily inside the async block
        // would silently drop the stroke with nothing inserted. Building the
        // element synchronously here means the async block only ever touches
        // values already captured by value in its closure.
        guard let canvasView = canvasReference?.canvasView,
              let elementsStore,
              let config = activeInkConfig,
              let captureBoundingBox = captureBoundingBox() else {
            return
        }

        let strokeColor = Self.styledStrokeColor(for: config)
        let strokeWidth = Self.styledStrokeWidth(for: config)
        let builtElement = ShapeElementBuilder.element(
            from: shape,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth
        )
        let isLine: Bool
        if case .polyline(let vertices, false) = shape, vertices.count == 2 {
            isLine = true
        } else {
            isLine = false
        }
        let currentPenPosition = capturedContentPoints.last
        let inflatedCaptureBoundingBox = captureBoundingBox.insetBy(
            dx: -Self.captureBoundsInflation,
            dy: -Self.captureBoundsInflation
        )

        let strokeCountBefore = canvasView.drawing.strokes.count
        canvasView.drawingGestureRecognizer.isEnabled = false
        hasSnappedThisStroke = true

        DispatchQueue.main.async { [weak self] in
            let liveSessionToken = elementsStore.beginLiveSession()
            elementsStore.mutateDrawingLive { drawing in
                let currentStrokeCount = drawing.strokes.count
                guard currentStrokeCount > strokeCountBefore else { return }
                let appendedStrokeRange = strokeCountBefore..<currentStrokeCount
                drawing.strokes = drawing.strokes.enumerated().compactMap {
                    index,
                    stroke in
                    if appendedStrokeRange.contains(index),
                       stroke.renderBounds.intersects(inflatedCaptureBoundingBox) {
                        return nil
                    }
                    return stroke
                }
            }
            let element = CanvasElement(
                content: .shape(builtElement.content),
                frame: builtElement.frame,
                rotation: builtElement.rotation
            )
            elementsStore.addElementLive(element)

            guard isLine else {
                canvasView.drawingGestureRecognizer.isEnabled = self?.isDrawingEnabled ?? true
                elementsStore.commitLiveSession(liveSessionToken, label: "Draw Shape")
                (canvasView as? PagedCanvasView)?.haptics.playSnapToFit()
                return
            }

            // If the controller is gone (note dismissed mid-snap), or the pen
            // already lifted while this block was queued, fail open rather than
            // leaving the PencilKit recognizer disabled with no future samples.
            guard let self,
                  self.isTrackingStroke,
                  self.hasSnappedThisStroke,
                  let currentPenPosition,
                  currentPenPosition.x.isFinite,
                  currentPenPosition.y.isFinite else {
                canvasView.drawingGestureRecognizer.isEnabled = self?.isDrawingEnabled ?? true
                elementsStore.commitLiveSession(liveSessionToken, label: "Draw Shape")
                (canvasView as? PagedCanvasView)?.haptics.playSnapToFit()
                return
            }

            let vertices = ShapeVertexEditor.absoluteVertices(
                content: builtElement.content,
                frame: builtElement.frame,
                rotation: builtElement.rotation
            )
            guard vertices.count == 2 else {
                canvasView.drawingGestureRecognizer.isEnabled = self.isDrawingEnabled
                elementsStore.commitLiveSession(liveSessionToken, label: "Draw Shape")
                (canvasView as? PagedCanvasView)?.haptics.playSnapToFit()
                return
            }

            let firstDistance = hypot(
                vertices[0].x - currentPenPosition.x,
                vertices[0].y - currentPenPosition.y
            )
            let secondDistance = hypot(
                vertices[1].x - currentPenPosition.x,
                vertices[1].y - currentPenPosition.y
            )
            let pivot = firstDistance >= secondDistance ? vertices[0] : vertices[1]
            self.lineAdjustState = LineAdjustState(
                elementID: element.id,
                pivot: pivot,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                liveSessionToken: liveSessionToken,
                isAxisSnapped: false
            )
            (canvasView as? PagedCanvasView)?.haptics.playSnapToFit()
        }
    }

    func strokeEnded(cancelled: Bool) {
        cancelPendingDwell()

        if let lineAdjustState {
            elementsStore?.commitLiveSession(
                lineAdjustState.liveSessionToken,
                label: "Draw Shape"
            )
            canvasReference?.canvasView?.drawingGestureRecognizer.isEnabled = isDrawingEnabled
            self.lineAdjustState = nil
            resetStrokeState()
            return
        }

        if case .snapOnLift = policy,
           !cancelled,
           let shape = pendingShapeToCommitOnLift,
           let captureBoundingBox = pendingCaptureBoundingBox {
            DispatchQueue.main.async { [weak self] in
                self?.commitShapeOnLift(
                    shape,
                    captureBoundingBox: captureBoundingBox
                )
            }
        }

        resetStrokeState()
    }

    static func styledStrokeColor(for config: InkToolConfig) -> CodableColor {
        guard config.style == .marker else { return config.color }
        var color = config.color
        color.alpha = 0.55
        return color
    }

    static func styledStrokeWidth(for config: InkToolConfig) -> Double {
        let range = NoteToolFactory.widthRange(for: config.style)
        return min(max(config.width, range.lowerBound), range.upperBound)
    }

    private func scheduleDwell(after delay: TimeInterval) {
        cancelPendingDwell()
        let generation = dwellScheduleGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.dwellScheduleGeneration == generation else {
                return
            }
            self.pendingDwellWorkItem = nil
            self.dwellFired()
        }
        pendingDwellWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingDwell() {
        pendingDwellWorkItem?.cancel()
        pendingDwellWorkItem = nil
        dwellScheduleGeneration += 1
    }

    private func commitShapeOnLift(
        _ shape: RecognizedShape,
        captureBoundingBox: CGRect
    ) {
        guard canvasReference?.canvasView != nil,
              let elementsStore,
              let config = activeInkConfig else {
            return
        }

        let strokeColor = Self.styledStrokeColor(for: config)
        let strokeWidth = Self.styledStrokeWidth(for: config)
        let builtElement = ShapeElementBuilder.element(
            from: shape,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth
        )
        let inflatedCaptureBoundingBox = captureBoundingBox.insetBy(
            dx: -Self.captureBoundsInflation,
            dy: -Self.captureBoundsInflation
        )

        let liveSessionToken = elementsStore.beginLiveSession()
        elementsStore.mutateDrawingLive { drawing in
            guard let lastStrokeIndex = drawing.strokes.indices.last,
                  drawing.strokes[lastStrokeIndex].renderBounds.intersects(
                      inflatedCaptureBoundingBox
                  ) else {
                return
            }
            drawing.strokes.remove(at: lastStrokeIndex)
        }
        elementsStore.addElementLive(
            CanvasElement(
                content: .shape(builtElement.content),
                frame: builtElement.frame,
                rotation: builtElement.rotation
            )
        )
        elementsStore.commitLiveSession(liveSessionToken, label: "Draw Shape")
    }

    private func captureBoundingBox() -> CGRect? {
        let finitePoints = capturedContentPoints.filter {
            $0.x.isFinite && $0.y.isFinite
        }
        guard let firstPoint = finitePoints.first else { return nil }

        var minimumX = firstPoint.x
        var maximumX = firstPoint.x
        var minimumY = firstPoint.y
        var maximumY = firstPoint.y
        for point in finitePoints.dropFirst() {
            minimumX = min(minimumX, point.x)
            maximumX = max(maximumX, point.x)
            minimumY = min(minimumY, point.y)
            maximumY = max(maximumY, point.y)
        }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    private func resetStrokeState() {
        detector.reset()
        capturedContentPoints.removeAll(keepingCapacity: true)
        isTrackingStroke = false
        hasSnappedThisStroke = false
        pendingShapeToCommitOnLift = nil
        pendingCaptureBoundingBox = nil
        lineAdjustState = nil
    }
}
