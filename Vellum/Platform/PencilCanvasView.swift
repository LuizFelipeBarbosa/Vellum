import Foundation
import PencilKit
import QuartzCore
import SwiftUI
import VellumCore

struct CanvasViewport: Equatable, Sendable {
    var contentOffset: CGPoint
    var zoomScale: CGFloat

    func viewPoint(fromContent p: CGPoint) -> CGPoint {
        CGPoint(
            x: p.x * zoomScale - contentOffset.x,
            y: p.y * zoomScale - contentOffset.y
        )
    }

    func contentPoint(fromView p: CGPoint) -> CGPoint {
        CGPoint(
            x: (p.x + contentOffset.x) / zoomScale,
            y: (p.y + contentOffset.y) / zoomScale
        )
    }

    func viewRect(fromContent r: CGRect) -> CGRect {
        CGRect(
            origin: viewPoint(fromContent: r.origin),
            size: CGSize(
                width: r.width * zoomScale,
                height: r.height * zoomScale
            )
        )
    }

    func visibleContentRect(viewportSize: CGSize) -> CGRect {
        CGRect(
            x: contentOffset.x / zoomScale,
            y: contentOffset.y / zoomScale,
            width: viewportSize.width / zoomScale,
            height: viewportSize.height / zoomScale
        )
    }
}

final class PagedCanvasView: PKCanvasView {
    let haptics = CanvasHaptics()
    private(set) var isAnimatingZoomSnap = false
    private var zoomSnapDisplayLink: CADisplayLink?
    private var zoomSnapStartScale: CGFloat = 0
    private var zoomSnapTargetScale: CGFloat = 0
    private var zoomSnapStartOffsetY: CGFloat = 0
    private var zoomSnapTargetOffsetY: CGFloat = 0
    private var zoomSnapStartTime: CFTimeInterval = 0
    private static let zoomSnapDuration: CFTimeInterval = 0.25
    private var isApplyingLayoutZoom = false

    /// True only while a SwiftUI representable update pass (`makeUIView`/`updateUIView`)
    /// is on the stack. Viewport reports are deferred only in this window because a
    /// synchronous @State write would modify state during a view update. UIKit layout
    /// passes such as rotation and split-view resize must report synchronously so overlay
    /// state commits in the same CATransaction as the canvas geometry change; otherwise
    /// the page lags the strokes by a frame.
    private(set) var isInRepresentableUpdate = false

    func performRepresentableUpdate(_ body: () -> Void) {
        let previous = isInRepresentableUpdate
        isInRepresentableUpdate = true
        defer { isInRepresentableUpdate = previous }
        body()
    }

    var topContentInset: CGFloat = 0 {
        didSet {
            guard oldValue != topContentInset else { return }
            let wasRestingAtTop = abs(contentOffset.y + oldValue) <= 0.5
            syncContentSize()
            if wasRestingAtTop {
                contentOffset.y = -topContentInset
            }
        }
    }

    // Placeholder until PencilCanvasView supplies the note-specific content height.
    var contentHeightInContentSpace: CGFloat = PageGeometry.a4.pageHeight {
        didSet {
            guard oldValue != contentHeightInContentSpace else { return }
            syncContentSize()
        }
    }
    private var lastLayoutSize: CGSize = .zero
    private var lastFitScale: CGFloat?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        updateZoomLimitsAndContentSize()
    }

    var expectedContentSize: CGSize {
        CGSize(width: PageLayout.contentWidth * zoomScale,
               height: contentHeightInContentSpace * zoomScale)
    }

    var fitZoomScale: CGFloat {
        PageLayout.minZoom(forViewportWidth: bounds.width)
    }

    func resyncContentSizeIfStomped() {
        let expected = expectedContentSize
        guard abs(contentSize.height - expected.height) > 0.5
           || abs(contentSize.width - expected.width) > 0.5 else { return }
        syncContentSize()
    }

    /// Safe on every zoom tick: re-derives scaled content size and horizontal centering.
    func syncContentSize() {
        contentSize = expectedContentSize
        centerContentHorizontally()
    }

    func centerContentHorizontally() {
        let excess = max(0, bounds.width - contentSize.width)
        contentInset.top = topContentInset
        contentInset.left = excess / 2
        contentInset.right = excess / 2
    }

    /// Explicit reset: animate to fit-to-width with the snap haptic.
    func snapZoomToFit() {
        animateZoomSnap(to: fitZoomScale)
    }

    /// A user gesture interrupts any in-flight snap animation; clear tracking so
    /// the next pinch gets haptics and its own snap decision.
    func userGestureWillBegin() {
        cancelZoomSnap()
    }

    /// Called from scrollViewDidEndZooming with the settled pinch scale.
    func handleZoomGestureEnded(atScale scale: CGFloat) {
        guard !isAnimatingZoomSnap else { return }
        guard let target = PageLayout.settleTargetZoom(
            forEndedZoomScale: scale,
            viewportWidth: bounds.width
        ), abs(scale - target) > 0.0001 else { return }

        animateZoomSnap(to: target)
    }

    private func animateZoomSnap(to target: CGFloat) {
        guard !isZooming else { return }
        guard abs(zoomScale - target) > 0.0001 else { return }

        cancelZoomSnap()
        zoomSnapStartScale = zoomScale
        zoomSnapTargetScale = target
        let visibleCenterContentY = (contentOffset.y + bounds.height / 2) / zoomScale
        zoomSnapStartOffsetY = contentOffset.y
        zoomSnapTargetOffsetY = PageLayout.anchoredOffsetY(
            visibleCenterContentY: visibleCenterContentY,
            scale: target,
            viewportHeight: bounds.height,
            contentHeight: contentHeightInContentSpace,
            minimumOffsetY: -topContentInset
        )
        isAnimatingZoomSnap = true
        haptics.prepare()
        haptics.playSnapToFit()
        let displayLink = CADisplayLink(target: self, selector: #selector(stepZoomSnap(_:)))
        zoomSnapDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
        zoomSnapStartTime = CACurrentMediaTime()
    }

    @objc private func stepZoomSnap(_ displayLink: CADisplayLink) {
        let t = min(
            1,
            (CACurrentMediaTime() - zoomSnapStartTime) / Self.zoomSnapDuration
        )
        let eased = CGFloat(1 - pow(1 - t, 3))
        zoomScale = zoomSnapStartScale
            + (zoomSnapTargetScale - zoomSnapStartScale) * eased
        contentOffset.y = zoomSnapStartOffsetY
            + (zoomSnapTargetOffsetY - zoomSnapStartOffsetY) * eased

        if t >= 1 {
            zoomScale = zoomSnapTargetScale
            contentOffset.y = zoomSnapTargetOffsetY
            finishZoomSnap()
        }
    }

    private func finishZoomSnap() {
        zoomSnapDisplayLink?.invalidate()
        zoomSnapDisplayLink = nil
        isAnimatingZoomSnap = false
        (delegate as? PencilCanvasView.Coordinator)?.flushPendingDrawingSyncIfNeeded(for: self)
    }

    func cancelZoomSnap() {
        zoomSnapDisplayLink?.invalidate()
        zoomSnapDisplayLink = nil
        isAnimatingZoomSnap = false
        (delegate as? PencilCanvasView.Coordinator)?.flushPendingDrawingSyncIfNeeded(for: self)
    }

    /// Called from scrollViewDidZoom: limit haptics (suppressed during programmatic snap).
    func handleZoomTick() {
        guard !isAnimatingZoomSnap, !isApplyingLayoutZoom else { return }
        haptics.zoomTick(
            scale: zoomScale,
            minScale: PageLayout.overviewMinZoom(forViewportWidth: bounds.width),
            maxScale: PageLayout.maxZoom(forViewportWidth: bounds.width)
        )
    }

    /// No horizontal drift at or below fit: pin the offset to the centered rest position.
    func lockHorizontalOffsetIfAtOrBelowFit() {
        guard contentSize.width <= bounds.width + 0.5 else { return }
        let centeredX = -contentInset.left
        if abs(contentOffset.x - centeredX) > 0.5 {
            contentOffset.x = centeredX
        }
    }

    /// Layout-driven: recompute fit limits and snap only outside an active pinch.
    func updateZoomLimitsAndContentSize() {
        guard bounds.width > 0 else { return }
        let isFirstLayout = lastFitScale == nil
        let fit = PageLayout.minZoom(forViewportWidth: bounds.width)
        let overviewFloor = PageLayout.overviewMinZoom(forViewportWidth: bounds.width)
        let wasAtFit = lastFitScale.map { abs(zoomScale - $0) < 0.001 } ?? false
        minimumZoomScale = PageLayout.elasticMinZoom(forViewportWidth: bounds.width)
        maximumZoomScale = PageLayout.elasticMaxZoom(forViewportWidth: bounds.width)
        isApplyingLayoutZoom = true
        if !isZooming {
            if lastFitScale == nil || wasAtFit {
                zoomScale = fit
            } else if zoomScale < overviewFloor {
                zoomScale = overviewFloor
            }
        }
        isApplyingLayoutZoom = false
        haptics.resetLimitLatch()
        lastFitScale = fit
        syncContentSize()
        if isFirstLayout {
            contentOffset.y = -topContentInset
        }
    }
}

enum PencilSqueezePhase: Sendable {
    case began
    case ended
}

@MainActor
struct PencilCanvasView: UIViewRepresentable {
    let drawingData: Data?
    let onDrawingChanged: (Data) -> Void
    var isTransparent: Bool = false
    var tool: (any PKTool)? = nil
    var showsSystemToolPicker: Bool = true
    var onCanvasReady: ((PKCanvasView) -> Void)? = nil
    var isDrawingEnabled: Bool = true
    // Placeholder overridden by NoteScreenView from NotePageState.
    var contentHeight: CGFloat = PageGeometry.a4.pageHeight
    var topContentInset: CGFloat = 0
    var onViewportChanged: ((CanvasViewport) -> Void)? = nil
    var onExternalDrawingChange: (() -> Void)? = nil
    var onPencilSqueeze: ((PencilSqueezePhase) -> Void)? = nil
    var onTwoFingerTap: (() -> Void)? = nil
    var onThreeFingerTap: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(
            onDrawingChanged: onDrawingChanged,
            onViewportChanged: onViewportChanged
        )
        coordinator.onExternalDrawingChange = onExternalDrawingChange
        coordinator.onPencilSqueeze = onPencilSqueeze
        coordinator.onTwoFingerTap = onTwoFingerTap
        coordinator.onThreeFingerTap = onThreeFingerTap
        return coordinator
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PagedCanvasView()
        canvasView.performRepresentableUpdate {
            canvasView.contentInsetAdjustmentBehavior = .never
            canvasView.contentHeightInContentSpace = contentHeight
            canvasView.topContentInset = topContentInset
            canvasView.delegate = context.coordinator
#if targetEnvironment(simulator)
            #if DEBUG
            canvasView.drawingPolicy = ProcessInfo.processInfo.arguments.contains("-vellum-force-pencil-only")
                ? .pencilOnly
                : .anyInput
            #else
            canvasView.drawingPolicy = .anyInput      // mouse can draw in the simulator
            #endif
#else
            canvasView.drawingPolicy = .pencilOnly    // fingers scroll & pinch; pencil draws
#endif
            canvasView.backgroundColor = isTransparent ? .clear : .white
            canvasView.isOpaque = !isTransparent
            canvasView.bouncesZoom = false
            canvasView.alwaysBounceVertical = true
            canvasView.drawingGestureRecognizer.isEnabled = isDrawingEnabled

            let undoTap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleTwoFingerTap(_:))
            )
            undoTap.numberOfTapsRequired = 1
            undoTap.numberOfTouchesRequired = 2
            undoTap.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
            undoTap.delegate = context.coordinator

            let redoTap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleThreeFingerTap(_:))
            )
            redoTap.numberOfTapsRequired = 1
            redoTap.numberOfTouchesRequired = 3
            redoTap.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
            redoTap.delegate = context.coordinator

            undoTap.require(toFail: redoTap)
            canvasView.addGestureRecognizer(undoTap)
            canvasView.addGestureRecognizer(redoTap)

            if #available(iOS 17.5, *) {
                canvasView.addInteraction(UIPencilInteraction(delegate: context.coordinator))
            }

            if let tool {
                canvasView.tool = tool
            }

            if showsSystemToolPicker {
                context.coordinator.toolPicker.addObserver(canvasView)
                context.coordinator.isObservingToolPicker = true
                context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
                canvasView.becomeFirstResponder()
            }

            onCanvasReady?(canvasView)
            context.coordinator.reportViewportDeferred(for: canvasView)
        }

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        let updateCanvas = {
            context.coordinator.onDrawingChanged = onDrawingChanged
            context.coordinator.onViewportChanged = onViewportChanged
            context.coordinator.onExternalDrawingChange = onExternalDrawingChange
            context.coordinator.onPencilSqueeze = onPencilSqueeze
            context.coordinator.onTwoFingerTap = onTwoFingerTap
            context.coordinator.onThreeFingerTap = onThreeFingerTap
            canvasView.backgroundColor = isTransparent ? .clear : .white
            canvasView.isOpaque = !isTransparent
            canvasView.drawingGestureRecognizer.isEnabled = isDrawingEnabled
            (canvasView as? PagedCanvasView)?.contentHeightInContentSpace = contentHeight
            (canvasView as? PagedCanvasView)?.topContentInset = topContentInset

            if let tool, !Self.toolsMatch(canvasView.tool, tool) {
                canvasView.tool = tool
            }

            let beganObservingToolPicker: Bool
            if showsSystemToolPicker {
                if !context.coordinator.isObservingToolPicker {
                    context.coordinator.toolPicker.addObserver(canvasView)
                    context.coordinator.isObservingToolPicker = true
                    context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
                    canvasView.becomeFirstResponder()
                    beganObservingToolPicker = true
                } else {
                    beganObservingToolPicker = false
                }
            } else if context.coordinator.isObservingToolPicker {
                context.coordinator.toolPicker.setVisible(false, forFirstResponder: canvasView)
                context.coordinator.toolPicker.removeObserver(canvasView)
                context.coordinator.isObservingToolPicker = false
                beganObservingToolPicker = false
            } else {
                beganObservingToolPicker = false
            }

            guard !context.coordinator.hasTransientDrawingOverride,
                  !canvasView.isZooming,
                  (canvasView as? PagedCanvasView)?.isAnimatingZoomSnap != true,
                  let drawingData,
                  drawingData != context.coordinator.lastSyncedDrawingData,
                  let drawing = try? PKDrawing(data: drawingData) else {
                return
            }

            context.coordinator.isUpdatingFromModel = true
            canvasView.drawing = drawing
            context.coordinator.isUpdatingFromModel = false
            context.coordinator.lastSyncedDrawingData = drawingData
            context.coordinator.onExternalDrawingChange?()

            if showsSystemToolPicker,
               !beganObservingToolPicker,
               canvasView.window != nil,
               !canvasView.isFirstResponder {
                context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
                canvasView.becomeFirstResponder()
            }
        }

        if let pagedCanvasView = canvasView as? PagedCanvasView {
            pagedCanvasView.performRepresentableUpdate(updateCanvas)
        } else {
            updateCanvas()
        }
    }

    static func dismantleUIView(_ canvasView: PKCanvasView, coordinator: Coordinator) {
        if coordinator.isObservingToolPicker {
            coordinator.toolPicker.removeObserver(canvasView)
        }
    }

    private static func toolsMatch(_ lhs: any PKTool, _ rhs: any PKTool) -> Bool {
        if let lhs = lhs as? PKInkingTool, let rhs = rhs as? PKInkingTool {
            return lhs == rhs
        }
        if let lhs = lhs as? PKEraserTool, let rhs = rhs as? PKEraserTool {
            return lhs == rhs
        }
        if let lhs = lhs as? PKLassoTool, let rhs = rhs as? PKLassoTool {
            return lhs == rhs
        }
        return false
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate,
        UIGestureRecognizerDelegate {
        let toolPicker = PKToolPicker()
        var onDrawingChanged: (Data) -> Void
        var onViewportChanged: ((CanvasViewport) -> Void)?
        var isProgrammaticChange = false
        private(set) var suppressedChangeOccurred = false
        var onExternalDrawingChange: (() -> Void)?
        var onPencilSqueeze: ((PencilSqueezePhase) -> Void)?
        var onTwoFingerTap: (() -> Void)?
        var onThreeFingerTap: (() -> Void)?
        var isUpdatingFromModel = false
        var lastSyncedDrawingData: Data?
        var isObservingToolPicker = false
        private var lastReportedViewport: CanvasViewport?
        private var hasPendingDeferredViewportReport = false
        private var hasPendingDrawingSyncAfterGesture = false
        /// True while the selection controller has intentionally diverged canvasView.drawing
        /// from the model (strokes hidden during a drag); updateUIView must not re-sync
        /// the canvas from drawingData while set.
        var hasTransientDrawingOverride = false

        init(
            onDrawingChanged: @escaping (Data) -> Void,
            onViewportChanged: ((CanvasViewport) -> Void)?
        ) {
            self.onDrawingChanged = onDrawingChanged
            self.onViewportChanged = onViewportChanged
        }

        func beginProgrammaticChange() {
            isProgrammaticChange = true
            suppressedChangeOccurred = false
        }

        func endProgrammaticChange(_ canvasView: PKCanvasView) {
            isProgrammaticChange = false
            if suppressedChangeOccurred {
                let drawingData = canvasView.drawing.dataRepresentation()
                lastSyncedDrawingData = drawingData
                onDrawingChanged(drawingData)
            }
        }

        func performSilentChange(_ body: () -> Void) {
            let wasProgrammaticChange = isProgrammaticChange
            let hadSuppressedChange = suppressedChangeOccurred
            isProgrammaticChange = true
            body()
            isProgrammaticChange = wasProgrammaticChange
            suppressedChangeOccurred = hadSuppressedChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            (canvasView as? PagedCanvasView)?.resyncContentSizeIfStomped()
            guard !isUpdatingFromModel else { return }
            if isProgrammaticChange {
                suppressedChangeOccurred = true
                return
            }
            // PencilKit can emit partial drawings while a zoom is in flight; defer the
            // model push until the gesture settles and the drawing is consistent again.
            if canvasView.isZooming
                || (canvasView as? PagedCanvasView)?.isAnimatingZoomSnap == true {
                hasPendingDrawingSyncAfterGesture = true
                return
            }
            let drawingData = canvasView.drawing.dataRepresentation()
            lastSyncedDrawingData = drawingData
            onDrawingChanged(drawingData)
            onExternalDrawingChange?()
        }

        fileprivate func flushPendingDrawingSyncIfNeeded(for canvasView: PKCanvasView) {
            guard hasPendingDrawingSyncAfterGesture else { return }
            guard !canvasView.isZooming,
                  (canvasView as? PagedCanvasView)?.isAnimatingZoomSnap != true else { return }
            hasPendingDrawingSyncAfterGesture = false
            let drawingData = canvasView.drawing.dataRepresentation()
            lastSyncedDrawingData = drawingData
            onDrawingChanged(drawingData)
            onExternalDrawingChange?()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            (scrollView as? PagedCanvasView)?.userGestureWillBegin()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            (scrollView as? PagedCanvasView)?.resyncContentSizeIfStomped()
            (scrollView as? PagedCanvasView)?.lockHorizontalOffsetIfAtOrBelowFit()
            reportViewport(for: scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? PagedCanvasView)?.syncContentSize()
            (scrollView as? PagedCanvasView)?.lockHorizontalOffsetIfAtOrBelowFit()
            (scrollView as? PagedCanvasView)?.handleZoomTick()
            reportViewport(for: scrollView)
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            (scrollView as? PagedCanvasView)?.userGestureWillBegin()
            (scrollView as? PagedCanvasView)?.haptics.prepare()
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with view: UIView?,
            atScale scale: CGFloat
        ) {
            (scrollView as? PagedCanvasView)?.syncContentSize()
            reportViewport(for: scrollView)
            (scrollView as? PagedCanvasView)?.handleZoomGestureEnded(atScale: scale)
            if let canvasView = scrollView as? PKCanvasView {
                flushPendingDrawingSyncIfNeeded(for: canvasView)
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Undo/redo taps must never fire alongside a pinch: a quick two-finger
            // pinch would otherwise also register as a tap and silently undo a stroke.
            !(otherGestureRecognizer is UIPinchGestureRecognizer)
        }

        @objc func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            if let canvasView = recognizer.view as? PKCanvasView,
               canvasView.isZooming || (canvasView as? PagedCanvasView)?.isAnimatingZoomSnap == true {
                return
            }
            onTwoFingerTap?()
        }

        @objc func handleThreeFingerTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            if let canvasView = recognizer.view as? PKCanvasView,
               canvasView.isZooming || (canvasView as? PagedCanvasView)?.isAnimatingZoomSnap == true {
                return
            }
            onThreeFingerTap?()
        }

        @available(iOS 17.5, *)
        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
            guard UIPencilInteraction.preferredSqueezeAction != .ignore else { return }
            switch squeeze.phase {
            case .began: onPencilSqueeze?(.began)
            case .changed: break
            case .ended, .cancelled: onPencilSqueeze?(.ended)
            @unknown default: onPencilSqueeze?(.ended)
            }
        }

        fileprivate func reportViewport(for scrollView: UIScrollView) {
            if (scrollView as? PagedCanvasView)?.isInRepresentableUpdate == true {
                reportViewportDeferred(for: scrollView)
                return
            }
            let viewport = CanvasViewport(
                contentOffset: scrollView.contentOffset,
                zoomScale: scrollView.zoomScale
            )
            guard viewport != lastReportedViewport else { return }
            lastReportedViewport = viewport
            onViewportChanged?(viewport)
        }

        /// For call sites inside a SwiftUI update pass (makeUIView), where a synchronous
        /// state write would be state-modification-during-view-update.
        /// Deferred delivery must never regress past a viewport already delivered
        /// synchronously by reportViewport, so it delivers the latest known viewport
        /// at fire time, making a stale or superseded Task idempotent instead of regressive.
        fileprivate func reportViewportDeferred(for scrollView: UIScrollView) {
            let viewport = CanvasViewport(
                contentOffset: scrollView.contentOffset,
                zoomScale: scrollView.zoomScale
            )
            guard viewport != lastReportedViewport else { return }
            lastReportedViewport = viewport
            if hasPendingDeferredViewportReport {
                return
            }
            hasPendingDeferredViewportReport = true
            Task { @MainActor in
                self.hasPendingDeferredViewportReport = false
                guard let latest = self.lastReportedViewport else { return }
                self.onViewportChanged?(latest)
            }
        }
    }
}
