import CoreGraphics
import Testing
@testable import VellumCore

@Suite("Drag auto-scroll")
struct DragAutoScrollTests {
    private let viewportLength: CGFloat = 500
    private let threshold: CGFloat = 48
    private let maxSpeed: CGFloat = 800

    @Test("Center of the viewport does not scroll")
    func centerDoesNotScroll() {
        #expect(velocity(at: viewportLength / 2) == 0)
    }

    @Test("Top edge scrolls up at maximum speed")
    func topEdgeScrollsAtMaximumSpeed() {
        #expect(velocity(at: 0) == -maxSpeed)
    }

    @Test("Bottom edge scrolls down at maximum speed")
    func bottomEdgeScrollsAtMaximumSpeed() {
        #expect(velocity(at: viewportLength) == maxSpeed)
    }

    @Test("Top band velocity is proportional to edge proximity")
    func topBandVelocityIsProportional() {
        let result = velocity(at: threshold / 2)

        #expect(abs(result - (-maxSpeed / 2)) < 0.000_001)
    }

    @Test("Positions just outside the edge bands do not scroll")
    func positionsOutsideBandsDoNotScroll() {
        #expect(velocity(at: threshold + 1) == 0)
        #expect(velocity(at: viewportLength - threshold - 1) == 0)
    }

    @Test("Viewport shorter than twice the threshold does not scroll")
    func degenerateViewportDoesNotScroll() {
        #expect(
            DragAutoScroll.velocity(
                position: 0,
                viewportLength: 2 * threshold - 1,
                threshold: threshold,
                maxSpeed: maxSpeed
            ) == 0
        )
    }

    private func velocity(at position: CGFloat) -> CGFloat {
        DragAutoScroll.velocity(
            position: position,
            viewportLength: viewportLength,
            threshold: threshold,
            maxSpeed: maxSpeed
        )
    }
}
