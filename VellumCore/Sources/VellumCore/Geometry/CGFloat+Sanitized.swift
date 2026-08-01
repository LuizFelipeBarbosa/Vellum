import CoreGraphics

extension CGFloat {
    /// The value itself when it is finite and non-negative, 0 otherwise.
    ///
    /// Lengths, insets, spans and tolerances are all quantities that cannot be negative
    /// and cannot be NaN. Sanitizing them once where they enter is what lets the
    /// arithmetic downstream stay plain arithmetic instead of re-checking every step.
    var nonnegativeFinite: CGFloat {
        isFinite ? Swift.max(0, self) : 0
    }
}
