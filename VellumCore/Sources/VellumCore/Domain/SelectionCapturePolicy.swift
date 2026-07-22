public enum CapturePointerKind: Sendable {
    case pencil
    case finger
}

public enum SelectionCapturePolicy {
    /// Whether a drag beginning with this pointer, at this position, may start.
    /// - Parameters:
    ///   - insideSelection: The touch began inside current selection bounds.
    ///   - allowsFingerCapture: Whether fingers may begin selection capture.
    public static func allowsDrag(
        pointer: CapturePointerKind,
        insideSelection: Bool,
        allowsFingerCapture: Bool
    ) -> Bool {
        switch pointer {
        case .pencil:
            true
        case .finger:
            insideSelection || allowsFingerCapture
        }
    }
}
