import CoreGraphics

/// Tracks arrival at zoom limits so a limit haptic fires once per visit,
/// with hysteresis so rubber-band jitter does not re-trigger it.
public struct ZoomLimitLatch {
    /// Fractional distance from a zoom limit required to release the latch.
    public static let releaseHysteresis: CGFloat = 0.02

    private var isLatched = false

    /// Creates an unlatched zoom-limit tracker.
    public init() {}

    /// Feed every zoom tick. Returns true exactly when a limit haptic should fire.
    public mutating func update(scale: CGFloat, minScale: CGFloat, maxScale: CGFloat) -> Bool {
        let atLimit = scale <= minScale * 1.001 || scale >= maxScale * 0.999
        guard !atLimit else {
            guard !isLatched else { return false }

            isLatched = true
            return true
        }

        let clearlyInside = scale > minScale * (1 + Self.releaseHysteresis)
            && scale < maxScale * (1 - Self.releaseHysteresis)
        guard clearlyInside else { return false }

        isLatched = false
        return false
    }

    /// Clears the latch so the next tick at a zoom limit fires again.
    public mutating func reset() {
        isLatched = false
    }
}
