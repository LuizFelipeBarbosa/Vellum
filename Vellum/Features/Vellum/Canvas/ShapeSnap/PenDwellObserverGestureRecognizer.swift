import UIKit

struct TimedPoint {
    let location: CGPoint
    let timestamp: TimeInterval
}

final class PenDwellObserverGestureRecognizer: UIGestureRecognizer {
    var allowsPencilTouches = true
    var allowsDirectTouches = false
    var onStrokeBegan: (() -> Void)?
    var onStrokePoints: (([TimedPoint]) -> Void)?
    var onStrokeEnded: ((_ cancelled: Bool) -> Void)?

    private weak var trackedTouch: UITouch?
    private var trackedTouchType: UITouch.TouchType?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            if let trackedTouch {
                if touch === trackedTouch {
                    continue
                }
                if trackedTouchType == .direct, touch.type == .direct {
                    abortTrackedStroke()
                    return
                }
                ignore(touch, for: event)
                continue
            }

            guard isEligible(touch) else {
                ignore(touch, for: event)
                continue
            }

            trackedTouch = touch
            trackedTouchType = touch.type
            onStrokeBegan?()
            emitSamples(for: touch, event: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch,
              let touch = touches.first(where: { $0 === trackedTouch }) else {
            return
        }
        emitSamples(for: touch, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finishTrackedStroke(in: touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finishTrackedStroke(in: touches, cancelled: true)
    }

    override func reset() {
        super.reset()
        // UIKit also resets on paths that never deliver touchesEnded/touchesCancelled
        // — the recognizer being disabled or detached mid-touch, for one. That is the
        // only stroke termination the observer would otherwise stay silent about,
        // leaving the controller stuck mid-stroke with PencilKit's drawing recognizer
        // still disabled.
        endTrackedStroke(cancelled: true)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    private func isEligible(_ touch: UITouch) -> Bool {
        (touch.type == .pencil && allowsPencilTouches)
            || (touch.type == .direct && allowsDirectTouches)
    }

    private func emitSamples(for touch: UITouch, event: UIEvent?) {
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        onStrokePoints?(
            samples.map {
                TimedPoint(
                    location: $0.location(in: view),
                    timestamp: $0.timestamp
                )
            }
        )
    }

    private func finishTrackedStroke(in touches: Set<UITouch>, cancelled: Bool) {
        guard let trackedTouch,
              touches.contains(where: { $0 === trackedTouch }) else {
            return
        }
        endTrackedStroke(cancelled: cancelled)
        state = .failed
    }

    private func abortTrackedStroke() {
        endTrackedStroke(cancelled: true)
        state = .failed
    }

    /// The one place `onStrokeEnded` is delivered. A tracked touch is the permit to
    /// report an end, and it is spent BEFORE the callback runs, so every termination
    /// notifies exactly once: assigning `state` (right after this returns) can make
    /// UIKit call `reset()`, and so can anything the callback itself does — either
    /// way the re-entrant path finds no tracked touch and stays quiet.
    private func endTrackedStroke(cancelled: Bool) {
        guard trackedTouch != nil else { return }
        clearTrackedTouch()
        onStrokeEnded?(cancelled)
    }

    private func clearTrackedTouch() {
        trackedTouch = nil
        trackedTouchType = nil
    }
}
