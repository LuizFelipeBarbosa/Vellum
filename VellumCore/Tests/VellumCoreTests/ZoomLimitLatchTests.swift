import CoreGraphics
import Testing
@testable import VellumCore

/// The seven-step hysteresis trace a naive `scale == limit` implementation cannot pass:
/// the latch fires on arrival, stays quiet while the pinch rubber-bands past the limit,
/// and only re-arms once the scale is clearly back inside — a near recovery must not do it.
/// The minimum and maximum sides run the same trace mirrored about their limit.
@Test("A zoom limit fires once until the latch clearly recovers", arguments: [
    // (limit, overshoot past the limit, near recovery, clear recovery)
    (CGFloat(1), CGFloat(0.95), CGFloat(1.01), CGFloat(1.03)),
    (CGFloat(4), CGFloat(4.1), CGFloat(3.97), CGFloat(3.9)),
])
func zoomLimitFiresOnceUntilClearRecovery(
    limit: CGFloat,
    overshoot: CGFloat,
    nearRecovery: CGFloat,
    clearRecovery: CGFloat
) {
    var latch = ZoomLimitLatch()
    func update(_ scale: CGFloat) -> Bool {
        latch.update(scale: scale, minScale: 1, maxScale: 4)
    }

    #expect(update(limit))
    #expect(!update(limit))
    #expect(!update(overshoot))
    #expect(!update(nearRecovery))
    #expect(!update(limit))
    #expect(!update(clearRecovery))
    #expect(update(limit))
}

@Test("Reset clears the zoom limit latch")
func resetClearsZoomLimitLatch() {
    var latch = ZoomLimitLatch()

    var shouldFire = latch.update(scale: 1, minScale: 1, maxScale: 4)
    #expect(shouldFire)
    latch.reset()
    shouldFire = latch.update(scale: 1, minScale: 1, maxScale: 4)
    #expect(shouldFire)
}
