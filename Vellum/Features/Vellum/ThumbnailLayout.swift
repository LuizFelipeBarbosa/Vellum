import CoreGraphics
import UIKit

enum ThumbnailLayout {
    static let width: CGFloat = 214
    static let badgeZone: CGFloat = 44
}

/// Convention for reorder feedback: medium = lift, selection = destination, light = drop.
/// Owner must call prepare() before first use so feedback lands without latency.
@MainActor
final class ReorderHaptics {
    private let liftGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let dropGenerator = UIImpactFeedbackGenerator(style: .light)

    func prepare() {
        liftGenerator.prepare()
        selectionGenerator.prepare()
        dropGenerator.prepare()
    }

    func liftOccurred() {
        liftGenerator.impactOccurred()
    }

    func selectionChanged() {
        selectionGenerator.selectionChanged()
    }

    func dropOccurred() {
        dropGenerator.impactOccurred()
    }
}
