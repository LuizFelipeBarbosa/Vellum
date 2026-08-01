import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

@Suite("Dwell detector")
struct DwellDetectorTests {
    private let config = DwellDetectorConfig(
        movementTolerance: 3,
        holdDuration: 0.6,
        minimumTravel: 12
    )

    /// Every case walks the pointer along the x axis, one sample each 0.1s. A stationary run
    /// can only begin once the pointer has travelled past the 12pt gate, and any step past
    /// the 3pt movement tolerance re-anchors it. The expectation is the index of the sample
    /// the run should start at, so the boundaries stay legible next to each other.
    @Test("Stationary runs start only after the travel gate", arguments: [
        // (x of each successive sample, index of the sample the run starts at)
        ([0, 13, 14] as [CGFloat], Int?.some(1)), // arms at the sample that crossed the gate
        ([0, 13, 14, 18], Int?.some(3)), // a 4pt step re-anchors the run
        ([0, 1, -1, 1], Int?.none), // never travels 12pt, so never arms
        ([0, 12, 15], Int?.some(1)), // 12pt and 3pt are both inclusive boundaries
    ])
    func stationaryRunStartsOnlyAfterTravelGate(xs: [CGFloat], armingIndex: Int?) {
        var detector = DwellDetector(config: config)
        let times = xs.indices.map { TimeInterval($0) / 10 }

        for (index, x) in xs.enumerated() {
            detector.ingest(CGPoint(x: x, y: 0), at: times[index])
        }

        #expect(detector.stationarySince == armingIndex.map { times[$0] })
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
