import CoreGraphics

public enum CapturePointerKind: Sendable {
    case pencil
    case finger
}

/// What a drag beginning on the canvas does while the select tool is active.
public enum SelectionDragIntent: Sendable {
    case move
    case capture
}

public enum SelectionCapturePolicy {
    /// Apple's minimum comfortable touch target, in screen points.
    static let minimumGrabTarget: CGFloat = 44
    /// Half the target on each side of the selection, so a selection with no interior at all
    /// still presents the whole target to aim at.
    static let grabPadding: CGFloat = minimumGrabTarget / 2

    /// The intent of a drag beginning with this pointer at this content-space location, or nil
    /// when the drag belongs to the canvas — scrolling — rather than to the selection surface.
    ///
    /// A selection is grabbed from a box one touch target larger than it is. A snapped line or a
    /// small shape has almost no interior to aim at, so demanding that the drag start inside the
    /// bounds made exactly those un-draggable: the gesture meant to move the selection replaced
    /// it with a fresh capture instead. Past that box the selection stays out of the way — a
    /// pencil captures a new one, and a finger falls through to the canvas wherever fingers do
    /// not capture, which is what keeps one-finger scrolling reachable while something is
    /// selected. The tradeoff is the padding itself: a drag starting just outside a selection
    /// moves it rather than doing what it would have done, and dropping the selection is what
    /// takes that back.
    ///
    /// - Parameters:
    ///   - location: Where the drag begins, in content space.
    ///   - selectionBounds: Bounds of the current selection in content space, or nil when
    ///     nothing is selected — or when a selection outlived the geometry that gave it bounds,
    ///     which leaves nothing on screen to grab and so must leave the drag to the canvas.
    ///   - zoomScale: Content-to-screen scale, used to keep the padding a screen measurement.
    ///   - allowsFingerCapture: Whether fingers may begin selection capture.
    public static func dragIntent(
        pointer: CapturePointerKind,
        location: CGPoint,
        selectionBounds: CGRect?,
        zoomScale: CGFloat,
        allowsFingerCapture: Bool
    ) -> SelectionDragIntent? {
        if let selectionBounds,
           grabArea(around: selectionBounds, zoomScale: zoomScale).contains(location) {
            return .move
        }
        switch pointer {
        case .pencil:
            return .capture
        case .finger:
            return allowsFingerCapture ? .capture : nil
        }
    }

    /// The selection's bounds grown by the touch target, in content space.
    ///
    /// The padding is a screen measurement divided by the zoom rather than a fixed content-space
    /// amount, because a content-space pad shrinks on screen as the user zooms out — exactly when
    /// a small shape is hardest to hit.
    static func grabArea(around bounds: CGRect, zoomScale: CGFloat) -> CGRect {
        // A zoom of zero has no content space to convert into, and the bare bounds are the
        // honest answer; the canvas surface never asks with one.
        guard zoomScale > 0 else { return bounds }
        let padding = grabPadding / zoomScale
        return bounds.insetBy(dx: -padding, dy: -padding)
    }
}
