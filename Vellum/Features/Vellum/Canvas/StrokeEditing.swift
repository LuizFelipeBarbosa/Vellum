import CoreGraphics
import Foundation
import PencilKit

/// Rebuilds `PKStroke`/`PKStrokePoint` values, which are immutable, for the page and selection
/// editors. Lives in the app target because `VellumCore` is deliberately PencilKit-free.
nonisolated enum StrokeEditing {
    /// Negative-determinant (flipping) transforms survive this round-trip; see
    /// `SelectionFlipTests.testPKStrokeAcceptsNegativeDeterminantTransform`.
    static func copy(_ stroke: PKStroke, applying transform: CGAffineTransform) -> PKStroke {
        PKStroke(
            ink: stroke.ink,
            path: stroke.path,
            transform: stroke.transform.concatenating(transform),
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
        )
    }

    static func copy(_ stroke: PKStroke, translatedBy translation: CGSize) -> PKStroke {
        copy(
            stroke,
            applying: CGAffineTransform(
                translationX: translation.width,
                y: translation.height
            )
        )
    }

    static func copy(
        _ point: PKStrokePoint,
        scalingTipBy factor: CGFloat
    ) -> PKStrokePoint {
        let size = CGSize(
            width: point.size.width * factor,
            height: point.size.height * factor
        )
        if #available(iOS 26.0, *) {
            return PKStrokePoint(
                location: point.location,
                timeOffset: point.timeOffset,
                size: size,
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude,
                secondaryScale: point.secondaryScale,
                threshold: point.threshold
            )
        }
        return PKStrokePoint(
            location: point.location,
            timeOffset: point.timeOffset,
            size: size,
            opacity: point.opacity,
            force: point.force,
            azimuth: point.azimuth,
            altitude: point.altitude,
            secondaryScale: point.secondaryScale
        )
    }

    static func averageTipWidth(of stroke: PKStroke) -> Double? {
        guard !stroke.path.isEmpty else { return nil }
        let total = stroke.path.reduce(CGFloat.zero) { partial, point in
            partial + point.size.width
        }
        return Double(total / CGFloat(stroke.path.count))
    }
}
