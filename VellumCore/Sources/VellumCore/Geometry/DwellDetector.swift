import CoreGraphics
import Foundation

public struct DwellDetectorConfig: Sendable {
    public var movementTolerance: CGFloat
    public var holdDuration: TimeInterval
    public var minimumTravel: CGFloat

    public static let `default` = DwellDetectorConfig(
        movementTolerance: 3,
        holdDuration: 0.6,
        minimumTravel: 12
    )

    public init(
        movementTolerance: CGFloat,
        holdDuration: TimeInterval,
        minimumTravel: CGFloat
    ) {
        self.movementTolerance = movementTolerance
        self.holdDuration = holdDuration
        self.minimumTravel = minimumTravel
    }
}

public struct DwellDetector: Sendable {
    public let config: DwellDetectorConfig
    public private(set) var stationarySince: TimeInterval?

    private var anchor: CGPoint?
    private var anchorTimestamp: TimeInterval?
    private var previousPoint: CGPoint?
    private var totalTravel: CGFloat = 0

    public init(config: DwellDetectorConfig = .default) {
        self.config = config
    }

    /// Feed every touch sample in order.
    public mutating func ingest(_ point: CGPoint, at timestamp: TimeInterval) {
        guard point.x.isFinite, point.y.isFinite, timestamp.isFinite else { return }

        guard let previousPoint, let anchor else {
            self.anchor = point
            anchorTimestamp = timestamp
            self.previousPoint = point
            stationarySince = minimumTravelReached ? timestamp : nil
            return
        }

        totalTravel += distance(from: previousPoint, to: point)
        self.previousPoint = point

        let tolerance = max(0, config.movementTolerance)
        if distance(from: anchor, to: point) > tolerance {
            self.anchor = point
            anchorTimestamp = timestamp
            stationarySince = minimumTravelReached ? timestamp : nil
        } else if stationarySince == nil, minimumTravelReached {
            stationarySince = anchorTimestamp
        }
    }

    public mutating func reset() {
        stationarySince = nil
        anchor = nil
        anchorTimestamp = nil
        previousPoint = nil
        totalTravel = 0
    }

    private var minimumTravelReached: Bool {
        totalTravel >= max(0, config.minimumTravel)
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }
}
