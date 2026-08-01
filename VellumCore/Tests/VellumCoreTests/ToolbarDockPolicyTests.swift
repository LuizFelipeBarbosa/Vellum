import CoreGraphics
import Testing
@testable import VellumCore

@Suite("Toolbar dock policy")
struct ToolbarDockPolicyTests {
    private let container = CGSize(width: 600, height: 400)
    private let toolbarSize = CGSize(width: 160, height: 48)
    private let insets = DockInsets()
    private let edgeMargin: CGFloat = 16
    private let accuracy: CGFloat = 0.000_001

    @Test("Dock edges expose the toolbar layout axis")
    func dockEdgesExposeLayoutAxis() {
        for edge in ToolbarDockEdge.allCases {
            switch edge {
            case .top, .bottom:
                #expect(edge.axis == .horizontal)
            case .left, .right:
                #expect(edge.axis == .vertical)
            }
        }
    }

    @Test("Bottom and right edges lead with the secondary section")
    func bottomAndRightEdgesLeadWithSecondarySection() {
        #expect(ToolbarDockEdge.top.secondarySectionLeads == false)
        #expect(ToolbarDockEdge.bottom.secondarySectionLeads)
        #expect(ToolbarDockEdge.left.secondarySectionLeads == false)
        #expect(ToolbarDockEdge.right.secondarySectionLeads)
    }

    @Test("Release points nearest each edge select that edge")
    func releasePointsSelectNearestEdge() {
        #expect(placement(for: CGPoint(x: 300, y: 20)).edge == .top)
        #expect(placement(for: CGPoint(x: 300, y: 380)).edge == .bottom)
        #expect(placement(for: CGPoint(x: 20, y: 200)).edge == .left)
        #expect(placement(for: CGPoint(x: 580, y: 200)).edge == .right)
    }

    @Test("Equal distances prefer bottom, then top, then left, then right")
    func equalDistancesUseStablePriority() {
        let bottomOverTop = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: 150, y: 50),
            toolbarSize: CGSize(width: 20, height: 20),
            container: CGSize(width: 300, height: 100),
            insets: insets,
            edgeMargin: 0
        )
        let topOverLeft = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: 30, y: 30),
            toolbarSize: CGSize(width: 20, height: 20),
            container: CGSize(width: 300, height: 300),
            insets: insets,
            edgeMargin: 0
        )
        let leftOverRight = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: 50, y: 150),
            toolbarSize: CGSize(width: 20, height: 20),
            container: CGSize(width: 100, height: 300),
            insets: insets,
            edgeMargin: 0
        )

        #expect(bottomOverTop.edge == .bottom)
        #expect(topOverLeft.edge == .top)
        #expect(leftOverRight.edge == .left)
    }

    @Test("Oversized toolbar axes fall back to the midpoint fraction")
    func oversizedToolbarAxesUseMidpointFraction() {
        let wideToolbar = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: 20, y: 0),
            toolbarSize: CGSize(width: 280, height: 40),
            container: CGSize(width: 300, height: 200),
            insets: insets,
            edgeMargin: edgeMargin
        )
        let tallToolbar = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: 0, y: 100),
            toolbarSize: CGSize(width: 80, height: 180),
            container: CGSize(width: 300, height: 200),
            insets: insets,
            edgeMargin: edgeMargin
        )

        #expect(wideToolbar.edge == .top)
        #expect(wideToolbar.fraction == 0.5)
        #expect(tallToolbar.edge == .left)
        #expect(tallToolbar.fraction == 0.5)
    }

    @Test("Fractions clamp near every end of an edge")
    func fractionsClampNearEdgeEnds() {
        let localContainer = CGSize(width: 300, height: 200)
        let localToolbar = CGSize(width: 100, height: 40)

        let topNearLeading = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: -40, y: 0),
            toolbarSize: localToolbar,
            container: localContainer,
            insets: insets,
            edgeMargin: edgeMargin
        )
        let topNearTrailing = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: 340, y: 0),
            toolbarSize: localToolbar,
            container: localContainer,
            insets: insets,
            edgeMargin: edgeMargin
        )
        let leftNearTop = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: 0, y: -40),
            toolbarSize: localToolbar,
            container: localContainer,
            insets: insets,
            edgeMargin: edgeMargin
        )
        let leftNearBottom = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: 0, y: 240),
            toolbarSize: localToolbar,
            container: localContainer,
            insets: insets,
            edgeMargin: edgeMargin
        )

        #expect(isApproximatelyEqual(topNearLeading.fraction, 66 / 300))
        #expect(isApproximatelyEqual(topNearTrailing.fraction, 234 / 300))
        #expect(isApproximatelyEqual(leftNearTop.fraction, 36 / 200))
        #expect(isApproximatelyEqual(leftNearBottom.fraction, 164 / 200))

        let leadingCenter = center(of: topNearLeading, toolbarSize: localToolbar, container: localContainer)
        let trailingCenter = center(of: topNearTrailing, toolbarSize: localToolbar, container: localContainer)
        let topCenter = center(of: leftNearTop, toolbarSize: localToolbar, container: localContainer)
        let bottomCenter = center(of: leftNearBottom, toolbarSize: localToolbar, container: localContainer)

        #expect(isApproximatelyEqual(leadingCenter.x, 66))
        #expect(isApproximatelyEqual(trailingCenter.x, 234))
        #expect(isApproximatelyEqual(topCenter.y, 36))
        #expect(isApproximatelyEqual(bottomCenter.y, 164))
    }

    @Test("A resolved center round-trips to the same placement")
    func resolvedCenterRoundTrips() {
        let original = ToolbarDockPlacement(edge: .bottom, fraction: 0.65)
        let resolvedCenter = center(of: original)
        let roundTrip = placement(for: resolvedCenter)

        #expect(roundTrip.edge == original.edge)
        #expect(isApproximatelyEqual(roundTrip.fraction, original.fraction))
    }

    @Test("Top inset moves a top-docked toolbar center down")
    func asymmetricTopInsetMovesToolbarDown() {
        let center = ToolbarDockPolicy.center(
            of: ToolbarDockPlacement(edge: .top, fraction: 0.5),
            toolbarSize: CGSize(width: 160, height: 40),
            container: container,
            insets: DockInsets(top: 80, leading: 10, bottom: 20, trailing: 30),
            edgeMargin: edgeMargin
        )

        #expect(center.y == 116)
    }

    @Test("Toolbar size does not change an unclamped release fraction")
    func toolbarSizeDoesNotChangeUnclampedFraction() {
        let releaseCenter = CGPoint(x: 240, y: 10)
        let collapsed = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: releaseCenter,
            toolbarSize: CGSize(width: 100, height: 40),
            container: container,
            insets: insets,
            edgeMargin: edgeMargin
        )
        let expanded = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: releaseCenter,
            toolbarSize: CGSize(width: 300, height: 80),
            container: container,
            insets: insets,
            edgeMargin: edgeMargin
        )

        #expect(collapsed.edge == .top)
        #expect(expanded.edge == .top)
        #expect(isApproximatelyEqual(collapsed.fraction, 0.4))
        #expect(isApproximatelyEqual(expanded.fraction, collapsed.fraction))
    }

    @Test("Degenerate containers return finite midpoint geometry")
    func degenerateContainersReturnFiniteValues() {
        let sizes = [
            CGSize.zero,
            CGSize(width: 20, height: 20),
            CGSize(width: 0.000_000_1, height: 0.000_000_1),
        ]

        for size in sizes {
            let placement = ToolbarDockPolicy.nearestPlacement(
                releaseCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                toolbarSize: CGSize(width: 10, height: 10),
                container: size,
                insets: insets,
                edgeMargin: edgeMargin
            )
            let resolvedCenter = center(
                of: placement,
                toolbarSize: CGSize(width: 10, height: 10),
                container: size
            )

            #expect(placement.fraction == 0.5)
            #expect(placement.fraction.isFinite)
            #expect(resolvedCenter.x.isFinite)
            #expect(resolvedCenter.y.isFinite)
        }

        let insetCollapsed = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: 70, y: 0),
            toolbarSize: .zero,
            container: CGSize(width: 100, height: 100),
            insets: DockInsets(
                leading: 49.999_999_96,
                trailing: 49.999_999_96
            ),
            edgeMargin: 0
        )

        #expect(insetCollapsed.edge == .top)
        #expect(insetCollapsed.fraction == 0.5)
    }

    @Test("A non-finite release point still docks somewhere inside the container")
    func nonFiniteReleasePointStillDocks() {
        let placement = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: CGFloat.nan, y: CGFloat.infinity),
            toolbarSize: toolbarSize,
            container: container,
            insets: insets,
            edgeMargin: edgeMargin
        )

        #expect(placement.fraction >= 0)
        #expect(placement.fraction <= 1)
        let point = center(of: placement)
        #expect(point.x.isFinite)
        #expect(point.y.isFinite)
    }

    @Test("A non-finite or out-of-range fraction resolves to a point inside the container")
    func nonFiniteFractionResolvesInsideContainer() {
        for fraction in [CGFloat.nan, -CGFloat.infinity, -5, 12] {
            let point = center(of: ToolbarDockPlacement(edge: .bottom, fraction: fraction))
            #expect(point.x >= toolbarSize.width / 2)
            #expect(point.x <= container.width - toolbarSize.width / 2)
            #expect(point.y.isFinite)
        }
    }

    @Test("Non-finite geometry is sanitized at the boundary, not per calculation")
    func nonFiniteGeometryIsSanitizedAtTheBoundary() {
        let placement = ToolbarDockPolicy.nearestPlacement(
            releaseCenter: CGPoint(x: 300, y: 380),
            toolbarSize: CGSize(width: CGFloat.nan, height: CGFloat.infinity),
            container: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 400),
            insets: DockInsets(top: .nan, leading: -CGFloat.infinity, bottom: 8, trailing: 8),
            edgeMargin: .nan
        )

        #expect(placement.fraction.isFinite)
        #expect(placement.fraction >= 0)
        #expect(placement.fraction <= 1)
    }

    private func placement(for releaseCenter: CGPoint) -> ToolbarDockPlacement {
        ToolbarDockPolicy.nearestPlacement(
            releaseCenter: releaseCenter,
            toolbarSize: toolbarSize,
            container: container,
            insets: insets,
            edgeMargin: edgeMargin
        )
    }

    private func center(
        of placement: ToolbarDockPlacement,
        toolbarSize: CGSize? = nil,
        container: CGSize? = nil
    ) -> CGPoint {
        ToolbarDockPolicy.center(
            of: placement,
            toolbarSize: toolbarSize ?? self.toolbarSize,
            container: container ?? self.container,
            insets: insets,
            edgeMargin: edgeMargin
        )
    }

    private func isApproximatelyEqual(_ first: CGFloat, _ second: CGFloat) -> Bool {
        abs(first - second) < accuracy
    }
}
