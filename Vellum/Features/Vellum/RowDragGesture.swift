import SwiftUI
import UIKit

@MainActor
private final class RowDragLongPressRecognizer: UILongPressGestureRecognizer {
    var onReset: (() -> Void)?

    override func reset() {
        super.reset()
        // UIKit does not send an action when a pending press fails. Reset is
        // the one lifecycle hook that also covers that possible-to-failed path.
        onReset?()
    }
}

/// Hold-to-lift drag for a vertical list inside a scroll view — the page-thumbnail panel and
/// the split-view note sidebar. `RowID` is whatever the list uses to name a row.
@MainActor
struct RowDragGesture<RowID>: UIGestureRecognizerRepresentable {
    /// Coordinate space the reported drag locations are converted into.
    let coordinateSpace: String
    /// Identifies the row under a touch, in the backing scroll view's content space.
    /// Returning nil refuses the touch, so the press never starts.
    let rowForContentPoint: (CGPoint) -> RowID?
    /// Called once the touch is accepted, while the press is still pending.
    let onPrepare: () -> Void
    let onBegin: (RowID, CGPoint) -> Void
    let onMove: (CGPoint) -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var rowForTouch: ((UIScrollView, UITouch) -> RowID?)?
        var activeRow: RowID?
        private weak var scrollView: UIScrollView?
        private weak var lockedScrollView: UIScrollView?
        private var wasScrollEnabled: Bool?

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // Gating happens before the recognizer owns the touch, so the
            // SwiftUI converter is unavailable. The nearest backing scroll
            // view supplies content-space coordinates directly because
            // scrolling changes its bounds origin, and avoids
            // rotation-sensitive window coordinates.
            var probe = touch.view
            while let view = probe, !(view is UIScrollView) {
                probe = view.superview
            }
            guard let scrollView = probe as? UIScrollView else { return false }
            self.scrollView = scrollView
            let row = rowForTouch?(scrollView, touch)

            // The first eligible touch fixes the dragged row while the press
            // is still possible. A second finger can land on a different row
            // before the long press resolves and must not retarget the drag.
            if gestureRecognizer.state == .possible, activeRow == nil {
                activeRow = row
            }

            return row != nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // Recognizing simultaneously with the scroll pan leaves nothing to fail
        // the press once a scroll has started, and allowableMovement alone lets
        // a slow scroll linger inside the press's window. This runs exactly at
        // the press's possible-to-began transition, so refusing here sends it to
        // failed and a list that is already moving keeps its touch.
        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let scrollView else { return true }
            return !scrollView.isDragging && !scrollView.isDecelerating
        }

        // Row selection is a SwiftUI Button whose tap recognizer would
        // otherwise claim row touches outright; requiring it to wait for the
        // long press to fail makes hold-to-drag win while quick taps still
        // act. Scroll pans stay exempt and recognize simultaneously, so
        // ordinary scrolling starts immediately; the scroll view is locked
        // only after the long press lifts a row. Invariant: every non-pan
        // recognizer in this subtree waits out the long press — if a new row
        // interaction (context menu, pinch, DragGesture) feels dead, check
        // here first.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            !(other is UIPanGestureRecognizer)
        }

        func lockScrolling() {
            guard lockedScrollView == nil, let scrollView else { return }
            lockedScrollView = scrollView
            wasScrollEnabled = scrollView.isScrollEnabled
            scrollView.isScrollEnabled = false
        }

        func restoreScrolling() {
            if let wasScrollEnabled {
                lockedScrollView?.isScrollEnabled = wasScrollEnabled
            }
            lockedScrollView = nil
            wasScrollEnabled = nil
        }
    }

    func makeCoordinator(
        converter: CoordinateSpaceConverter
    ) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(
        context: Context
    ) -> UILongPressGestureRecognizer {
        let recognizer = RowDragLongPressRecognizer()
        context.coordinator.rowForTouch = gate
        recognizer.delegate = context.coordinator
        recognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
        ]
        recognizer.onReset = {
            context.coordinator.activeRow = nil
        }
        configure(recognizer)
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        context.coordinator.rowForTouch = gate
        configure(recognizer)
    }

    private var gate: (UIScrollView, UITouch) -> RowID? {
        { scrollView, touch in
            guard let row = rowForContentPoint(touch.location(in: scrollView)) else {
                return nil
            }
            onPrepare()
            return row
        }
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        switch recognizer.state {
        case .began:
            context.coordinator.lockScrolling()
            guard let row = context.coordinator.activeRow else {
                onCancel()
                return
            }
            onBegin(row, convertedLocation(context: context))
        case .changed:
            onMove(convertedLocation(context: context))
        case .ended:
            context.coordinator.restoreScrolling()
            onEnd()
        case .cancelled, .failed:
            context.coordinator.restoreScrolling()
            onCancel()
        case .possible:
            break
        @unknown default:
            context.coordinator.restoreScrolling()
            onCancel()
        }
    }

    private func configure(_ recognizer: UILongPressGestureRecognizer) {
        recognizer.minimumPressDuration = 0.3
        recognizer.allowableMovement = 24
        recognizer.numberOfTouchesRequired = 1
        recognizer.cancelsTouchesInView = true
    }

    private func convertedLocation(context: Context) -> CGPoint {
        context.converter.location(in: .named(coordinateSpace))
    }
}
