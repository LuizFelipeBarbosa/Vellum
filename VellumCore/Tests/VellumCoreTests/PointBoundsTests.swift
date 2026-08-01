import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

@Test("Bounds cover every point and expose the extent")
func boundsCoverEveryPoint() throws {
    let bounds = try #require(
        PointBounds(of: [CGPoint(x: 3, y: -2), CGPoint(x: -1, y: 4), CGPoint(x: 0, y: 1)])
    )

    #expect(bounds.minimumX == -1)
    #expect(bounds.maximumX == 3)
    #expect(bounds.minimumY == -2)
    #expect(bounds.maximumY == 4)
    #expect(bounds.width == 4)
    #expect(bounds.height == 6)
    #expect(bounds.midpoint == CGPoint(x: 1, y: 1))
    #expect(bounds.diagonal == hypot(4, 6))
}

@Test("A single point bounds an empty extent")
func singlePointHasNoExtent() throws {
    let bounds = try #require(PointBounds(of: [CGPoint(x: 5, y: 5)]))

    #expect(bounds.width == 0)
    #expect(bounds.height == 0)
    #expect(bounds.midpoint == CGPoint(x: 5, y: 5))
}

@Test("No points and non-finite points have no bounds")
func nonFiniteInputHasNoBounds() {
    #expect(PointBounds(of: []) == nil)
    #expect(PointBounds(of: [CGPoint(x: CGFloat.nan, y: 0)]) == nil)
    #expect(PointBounds(of: [CGPoint(x: 0, y: 0), CGPoint(x: CGFloat.infinity, y: 1)]) == nil)
    #expect(PointBounds(of: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: -CGFloat.infinity)]) == nil)
}
