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
    /// The intent of a drag beginning with this pointer, or nil when the drag belongs to the
    /// canvas — scrolling — rather than to the selection surface.
    ///
    /// A selection makes moving it the primary gesture: any drag moves it, from any pointer,
    /// wherever it starts. Small items have no room to grab inside their own bounds, so the
    /// whole page becomes the grab area. One-finger scrolling and a fresh capture both need
    /// the selection dropped first, which a tap outside it already does; two fingers still
    /// scroll and zoom the canvas either way.
    ///
    /// - Parameters:
    ///   - hasSelection: A selection currently exists.
    ///   - allowsFingerCapture: Whether fingers may begin selection capture.
    public static func dragIntent(
        pointer: CapturePointerKind,
        hasSelection: Bool,
        allowsFingerCapture: Bool
    ) -> SelectionDragIntent? {
        if hasSelection {
            return .move
        }
        switch pointer {
        case .pencil:
            return .capture
        case .finger:
            return allowsFingerCapture ? .capture : nil
        }
    }
}
