import CoreGraphics
import Testing
@testable import VellumCore

@Suite("Dwell detector")
struct DwellDetectorTests {
    private let config = DwellDetectorConfig(
        movementTolerance: 3,
        holdDuration: 0.6,
        minimumTravel: 12
    )

    @Test("Stationary run arms after the travel gate")
    func stationaryRunArmsAfterTravelGate() {
        var detector = DwellDetector(config: config)

        detector.ingest(CGPoint(x: 0, y: 0), at: 0)
        detector.ingest(CGPoint(x: 13, y: 0), at: 0.1)
        detector.ingest(CGPoint(x: 14, y: 0), at: 0.2)

        #expect(detector.stationarySince == 0.1)
    }

    @Test("Movement beyond tolerance starts a new stationary run")
    func movementBeyondToleranceReanchors() {
        var detector = DwellDetector(config: config)

        detector.ingest(CGPoint(x: 0, y: 0), at: 0)
        detector.ingest(CGPoint(x: 13, y: 0), at: 0.1)
        detector.ingest(CGPoint(x: 14, y: 0), at: 0.2)
        detector.ingest(CGPoint(x: 18, y: 0), at: 0.3)

        #expect(detector.stationarySince == 0.3)
    }

    @Test("A stationary cluster cannot arm before minimum travel")
    func stationaryClusterDoesNotArmEarly() {
        var detector = DwellDetector(config: config)

        detector.ingest(CGPoint(x: 0, y: 0), at: 0)
        detector.ingest(CGPoint(x: 1, y: 0), at: 0.1)
        detector.ingest(CGPoint(x: -1, y: 0), at: 0.2)
        detector.ingest(CGPoint(x: 1, y: 0), at: 0.3)

        #expect(detector.stationarySince == nil)
    }

    @Test("Movement tolerance is inclusive")
    func movementToleranceIsInclusive() {
        var detector = DwellDetector(config: config)

        detector.ingest(CGPoint(x: 0, y: 0), at: 0)
        detector.ingest(CGPoint(x: 12, y: 0), at: 0.1)
        detector.ingest(CGPoint(x: 15, y: 0), at: 0.2)

        #expect(detector.stationarySince == 0.1)
    }

    @Test("Reset clears the travel gate and stationary state")
    func resetClearsAllState() {
        var detector = DwellDetector(config: config)

        detector.ingest(CGPoint(x: 0, y: 0), at: 0)
        detector.ingest(CGPoint(x: 13, y: 0), at: 0.1)
        #expect(detector.stationarySince == 0.1)

        detector.reset()
        #expect(detector.stationarySince == nil)

        detector.ingest(CGPoint(x: 100, y: 100), at: 1)
        detector.ingest(CGPoint(x: 101, y: 100), at: 1.1)
        detector.ingest(CGPoint(x: 99, y: 100), at: 1.2)

        #expect(detector.stationarySince == nil)
    }
}
