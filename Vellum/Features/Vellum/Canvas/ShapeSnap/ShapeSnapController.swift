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
    /// Alignment lattice for a content-space point, or nil where there is nothing to align to.
    /// Supplied by the note screen, which is what knows the page background.
    var snapGrid: ((CGPoint) -> ShapeSnapGrid?)?
    var isDrawingEnabled = true
    let policy: ShapeSnapPolicy

    // Per-stroke scratch state. None of it is read from a SwiftUI body — only from
    // this controller and its gesture callbacks — and `capturedContentPoints` alone
    // is written once per touch sample (up to ~240 Hz on Pencil). Left observable it
    // would invalidate every view holding this controller at sample rate.
    @ObservationIgnored private var detector = DwellDetector()
    @ObservationIgnored var capturedContentPoints: [CGPoint] = []
    @ObservationIgnored private var pendingDwellWorkItem: DispatchWorkItem?
    @ObservationIgnored private var isTrackingStroke = false
    @ObservationIgnored private var hasSnappedThisStroke = false
    @ObservationIgnored var pendingShapeToCommitOnLift: RecognizedShape?
    @ObservationIgnored private var pendingLiftSnap: PendingLiftSnap?

    /// What the dwell hands to the deferred on-lift commit. The box and the stroke
    /// count are sampled together, so they can never describe different moments —
    /// the commit needs both to tell the ink it is replacing apart from the strokes
    /// that were already on the page.
    private struct PendingLiftSnap {
        let captureBoundingBox: CGRect
        let strokeCountBeforeInk: Int
    }

    private struct LineAdjustState {
        let elementID: UUID
        let pivot: CGPoint
        let strokeColor: CodableColor
        let strokeWidth: Double
        let liveSessionToken: CanvasElementsStore.LiveSessionToken
        var isAxisSnapped: Bool
    }

    private var lineAdjustState: LineAdjustState?
    /// Set once a stroke outgrows `capturePointLimit`: recognition is off for the
    /// rest of that stroke, and `capturedContentPoints` stays empty.
    private var hasAbandonedCapture = false
    private var dwellScheduleGeneration = 0
    private static let capturePointLimit = 4_096
    private static let captureBoundsInflation: CGFloat = 20

    init(policy: ShapeSnapPolicy = ShapeSnapPolicy.resolveFromLaunchArguments()) {
        self.policy = policy
    }

    func strokeBegan() {
        // A stroke can terminate without ever reaching `strokeEnded` (a gesture
        // reset, a canvas swap), leaving a live line adjustment open. Close it here
        // before anything else: a stale pivot would otherwise redirect this stroke
        // into rewriting the previous element, and PencilKit's drawing recognizer
        // would stay disabled. Runs even while disabled — this is cleanup, not work.
        finishLineAdjustment()

        guard isEnabled else { return }

        detector.reset()
        capturedContentPoints.removeAll(keepingCapacity: true)
        cancelPendingDwell()
        isTrackingStroke = true
        hasSnappedThisStroke = false
        hasAbandonedCapture = false
        pendingShapeToCommitOnLift = nil
        pendingLiftSnap = nil
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
                from: alignedToPageGrid(
                    .polyline(
                        vertices: [lineAdjustState.pivot, adjusted.point],
                        isClosed: false
                    ),
                    near: lineAdjustState.pivot
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

        guard !hasSnappedThisStroke, !hasAbandonedCapture else { return }

        // A stroke this long is a scribble, not a shape. Trimming the front of the
        // capture would only pretend otherwise: `isClosedStroke` compares the first
        // and last captured points, so a trimmed stroke could never read as closed.
        // Give up on recognition for the rest of the stroke — PencilKit keeps inking
        // it, we just stop watching.
        guard capturedContentPoints.count + points.count <= Self.capturePointLimit else {
            hasAbandonedCapture = true
            capturedContentPoints.removeAll(keepingCapacity: false)
            detector.reset()
            cancelPendingDwell()
            return
        }

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
            .map { alignedToPageGrid($0, near: capturedContentPoints[0]) }
        cancelPendingDwell()
        detector.reset()
        guard let shape else { return }

        switch policy {
        case .snapMidStroke:
            performMidStrokeSnap(shape: shape)
        case .snapOnLift:
            pendingShapeToCommitOnLift = shape
            // Sample the stroke count HERE, with the pen still down: PencilKit cannot
            // have appended this stroke yet, so every stroke past this index is ink
            // from it. Sampling at the lift instead would be a coin toss — PencilKit
            // does not promise to have committed the stroke by then, and whenever it
            // has not, the last stroke is the user's PREVIOUS one.
            pendingLiftSnap = captureBoundingBox().map {
                PendingLiftSnap(
                    captureBoundingBox: $0,
                    strokeCountBeforeInk: canvasView.drawing.strokes.count
                )
            }
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

        if finishLineAdjustment() {
            resetStrokeState()
            return
        }

        // Resolve every input the deferred commit needs NOW, for the reason spelled
        // out in `performMidStrokeSnap`: a tool switch or a view teardown between
        // this lift and the next runloop turn would leave `activeInkConfig` /
        // `elementsStore` cleared, and the commit would silently drop the shape.
        if case .snapOnLift = policy,
           !cancelled,
           let shape = pendingShapeToCommitOnLift,
           let pendingLiftSnap,
           canvasReference?.canvasView != nil,
           let elementsStore,
           let config = activeInkConfig {
            DispatchQueue.main.async {
                ShapeSnapController.commitShapeOnLift(
                    shape,
                    pendingLiftSnap: pendingLiftSnap,
                    elementsStore: elementsStore,
                    config: config
                )
            }
        }

        resetStrokeState()
    }

    /// Closes an in-flight live line adjustment: registers its single undo step and
    /// hands PencilKit's drawing recognizer back. Returns whether one was open.
    @discardableResult
    private func finishLineAdjustment() -> Bool {
        guard let lineAdjustState else { return false }

        self.lineAdjustState = nil
        elementsStore?.commitLiveSession(
            lineAdjustState.liveSessionToken,
            label: "Draw Shape"
        )
        canvasReference?.canvasView?.drawingGestureRecognizer.isEnabled = isDrawingEnabled
        return true
    }

    /// Pulls an axis-aligned shape onto the page's rules, grid, or dots. Tilted shapes come back
    /// untouched — `ShapeGridSnapper` makes that call, so every snap site shares one rule.
    private func alignedToPageGrid(
        _ shape: RecognizedShape,
        near point: CGPoint
    ) -> RecognizedShape {
        ShapeGridSnapper.snapped(shape, to: snapGrid?(point))
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

    /// Static on purpose: every input arrives by value from `strokeEnded`, so the
    /// commit cannot be derailed by controller state that moved on in the meantime.
    private static func commitShapeOnLift(
        _ shape: RecognizedShape,
        pendingLiftSnap: PendingLiftSnap,
        elementsStore: CanvasElementsStore,
        config: InkToolConfig
    ) {
        let inflatedCaptureBoundingBox = pendingLiftSnap.captureBoundingBox.insetBy(
            dx: -Self.captureBoundsInflation,
            dy: -Self.captureBoundsInflation
        )

        let liveSessionToken = elementsStore.beginLiveSession()
        var didRemoveInkedStroke = false
        elementsStore.mutateDrawingLive { drawing in
            // Only strokes appended since the dwell can be this stroke's ink. Bounds
            // alone cannot tell them apart from an older sketch drawn in the same
            // place — and PencilKit may not have appended anything yet at all.
            let currentStrokeCount = drawing.strokes.count
            guard currentStrokeCount > pendingLiftSnap.strokeCountBeforeInk else { return }
            let appendedStrokeRange = pendingLiftSnap.strokeCountBeforeInk..<currentStrokeCount
            drawing.strokes = drawing.strokes.enumerated().compactMap { index, stroke in
                if appendedStrokeRange.contains(index),
                   stroke.renderBounds.intersects(inflatedCaptureBoundingBox) {
                    didRemoveInkedStroke = true
                    return nil
                }
                return stroke
            }
        }

        // The snapped shape exists to stand in for the ink it replaces. Failing to find
        // that ink means we cannot say what this shape is standing in for, so inserting
        // it would leave the user's sketch AND a perfect copy of it stacked on the page.
        // Drop the snap instead: what the user drew is still there, untouched.
        guard didRemoveInkedStroke else { return }

        let builtElement = ShapeElementBuilder.element(
            from: shape,
            strokeColor: Self.styledStrokeColor(for: config),
            strokeWidth: Self.styledStrokeWidth(for: config)
        )
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
        hasAbandonedCapture = false
        pendingShapeToCommitOnLift = nil
        pendingLiftSnap = nil
        lineAdjustState = nil
    }
}
