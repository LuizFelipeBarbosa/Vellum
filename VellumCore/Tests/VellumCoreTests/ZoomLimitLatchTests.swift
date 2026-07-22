import Testing
@testable import VellumCore

@Test("Minimum zoom limit fires once until the latch clearly recovers")
func minimumZoomLimitFiresOnceUntilClearRecovery() {
    var latch = ZoomLimitLatch()

    var shouldFire = latch.update(scale: 1, minScale: 1, maxScale: 4)
    #expect(shouldFire)
    shouldFire = latch.update(scale: 1, minScale: 1, maxScale: 4)
    #expect(!shouldFire)
    shouldFire = latch.update(scale: 0.95, minScale: 1, maxScale: 4)
    #expect(!shouldFire)
    shouldFire = latch.update(scale: 1.01, minScale: 1, maxScale: 4)
    #expect(!shouldFire)
    shouldFire = latch.update(scale: 1, minScale: 1, maxScale: 4)
    #expect(!shouldFire)
    shouldFire = latch.update(scale: 1.03, minScale: 1, maxScale: 4)
    #expect(!shouldFire)
    shouldFire = latch.update(scale: 1, minScale: 1, maxScale: 4)
    #expect(shouldFire)
}

@Test("Maximum zoom limit fires once until the latch clearly recovers")
func maximumZoomLimitFiresOnceUntilClearRecovery() {
    var latch = ZoomLimitLatch()

    var shouldFire = latch.update(scale: 4, minScale: 1, maxScale: 4)
    #expect(shouldFire)
    shouldFire = latch.update(scale: 4, minScale: 1, maxScale: 4)
    #expect(!shouldFire)
    shouldFire = latch.update(scale: 4.1, minScale: 1, maxScale: 4)
    #expect(!shouldFire)
    shouldFire = latch.update(scale: 3.97, minScale: 1, maxScale: 4)
    #expect(!shouldFire)
    shouldFire = latch.update(scale: 4, minScale: 1, maxScale: 4)
    #expect(!shouldFire)
    shouldFire = latch.update(scale: 3.9, minScale: 1, maxScale: 4)
    #expect(!shouldFire)
    shouldFire = latch.update(scale: 4, minScale: 1, maxScale: 4)
    #expect(shouldFire)
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
