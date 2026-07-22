import CoreGraphics

public enum DragAutoScroll {
    /// Points-per-second scroll velocity for a drag at `position` within a viewport of `length`.
    /// Negative scrolls toward zero (up), positive scrolls forward (down), zero outside the bands.
    public static func velocity(
        position: CGFloat,
        viewportLength: CGFloat,
        threshold: CGFloat = 48,
        maxSpeed: CGFloat = 800
    ) -> CGFloat {
        guard threshold > 0, viewportLength > 2 * threshold else { return 0 }

        if position < threshold {
            return -maxSpeed * min(1, (threshold - position) / threshold)
        }
        if position > viewportLength - threshold {
            return maxSpeed * min(
                1,
                (position - (viewportLength - threshold)) / threshold
            )
        }
        return 0
    }
}
