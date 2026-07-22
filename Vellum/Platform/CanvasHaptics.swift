import UIKit
import VellumCore

/// Convention for canvas feedback: rigid = decisive snap, soft = boundary touch.
/// Owner must call prepare() when a gesture begins so impacts land without latency.
@MainActor
final class CanvasHaptics {
    private let snapGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let limitGenerator = UIImpactFeedbackGenerator(style: .soft)
    private var limitLatch = ZoomLimitLatch()

    func prepare() {
        snapGenerator.prepare()
        limitGenerator.prepare()
    }

    func playSnapToFit() {
        snapGenerator.impactOccurred()
    }

    func zoomTick(scale: CGFloat, minScale: CGFloat, maxScale: CGFloat) {
        guard limitLatch.update(
            scale: scale,
            minScale: minScale,
            maxScale: maxScale
        ) else { return }

        limitGenerator.impactOccurred()
    }

    func resetLimitLatch() {
        limitLatch.reset()
    }
}
