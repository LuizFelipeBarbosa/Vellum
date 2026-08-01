import CoreGraphics

/// The quarter turn nearest an angle, when the angle is close enough to count as
/// axis-aligned. Recognition, line dragging and grid snapping all ask this same
/// question; they differ only in the tolerance they allow and in what they do with
/// the answer.
struct QuarterTurn {
    /// Quarter turns from zero, kept as a float rather than an `Int`: an angle far
    /// from the origin rounds to a count no `Int` can hold, and only the exact angle
    /// and the parity are ever needed.
    private let turns: CGFloat

    /// The exact axis-aligned angle, in radians.
    var angle: CGFloat { turns * (.pi / 2) }

    /// True at a quarter and three-quarter turn, where width and height exchange places.
    var swapsAxes: Bool { abs(turns).truncatingRemainder(dividingBy: 2) == 1 }

    /// nil when `angle` sits further than `tolerance` radians from every quarter turn,
    /// which every caller reads as "leave the angle alone". A non-finite angle is never
    /// near one, and a non-finite tolerance snaps nothing rather than everything.
    init?(nearest angle: CGFloat, tolerance: CGFloat) {
        let quarterTurn = CGFloat.pi / 2
        let turns = (angle / quarterTurn).rounded()
        guard abs(angle - turns * quarterTurn) <= tolerance.nonnegativeFinite else {
            return nil
        }
        self.turns = turns
    }

    init?(nearest angle: CGFloat, toleranceDegrees: CGFloat) {
        self.init(nearest: angle, tolerance: toleranceDegrees.nonnegativeFinite * .pi / 180)
    }
}
