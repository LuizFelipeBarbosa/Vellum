import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

private let quarter = CGFloat.pi / 2

@Test("An angle inside the tolerance reports the exact quarter turn")
func snapsInsideTolerance() throws {
    let turn = try #require(QuarterTurn(nearest: quarter + 0.05, tolerance: 0.1))

    #expect(turn.angle == quarter)
    #expect(turn.swapsAxes)
}

@Test("An angle outside the tolerance has no quarter turn")
func doesNotSnapOutsideTolerance() {
    #expect(QuarterTurn(nearest: quarter + 0.2, tolerance: 0.1) == nil)
    #expect(QuarterTurn(nearest: 0.001, tolerance: 0) == nil)
    #expect(QuarterTurn(nearest: 0, tolerance: 0)?.angle == 0)
}

@Test("Exactly half way rounds away from zero on both signs")
func halfWayRoundsAwayFromZero() throws {
    let tolerance = CGFloat.pi / 4 + 0.001

    let positive = try #require(QuarterTurn(nearest: .pi / 4, tolerance: tolerance))
    let negative = try #require(QuarterTurn(nearest: -.pi / 4, tolerance: tolerance))

    #expect(positive.angle == quarter)
    #expect(negative.angle == -quarter)
}

@Test("Negative and beyond-full-turn angles keep their sign and parity")
func handlesNegativeAndLargeAngles() throws {
    let threeQuarters = try #require(QuarterTurn(nearest: -3 * quarter - 0.01, tolerance: 0.1))
    #expect(threeQuarters.angle == -3 * quarter)
    #expect(threeQuarters.swapsAxes)

    let fullTurn = try #require(QuarterTurn(nearest: 4 * quarter + 0.01, tolerance: 0.1))
    #expect(fullTurn.angle == 4 * quarter)
    #expect(!fullTurn.swapsAxes)

    let fiveQuarters = try #require(QuarterTurn(nearest: 5 * quarter, tolerance: 0.1))
    #expect(fiveQuarters.swapsAxes)
}

@Test("A degree tolerance matches the radian one it converts to")
func degreeToleranceMatchesRadians() throws {
    let eightDegrees = max(0, CGFloat(8)) * .pi / 180
    let justInside = eightDegrees - 0.0001

    #expect(QuarterTurn(nearest: justInside, toleranceDegrees: 8)?.angle == 0)
    #expect(QuarterTurn(nearest: eightDegrees + 0.0001, toleranceDegrees: 8) == nil)
}

@Test("Non-finite angles and tolerances never snap")
func nonFiniteInputNeverSnaps() {
    #expect(QuarterTurn(nearest: .nan, tolerance: 1) == nil)
    #expect(QuarterTurn(nearest: .infinity, tolerance: 1) == nil)
    // An infinite tolerance snapping everything would be worse than snapping nothing.
    #expect(QuarterTurn(nearest: 1, tolerance: .infinity) == nil)
    #expect(QuarterTurn(nearest: 1, toleranceDegrees: .infinity) == nil)
    #expect(QuarterTurn(nearest: 1, toleranceDegrees: .nan) == nil)
    #expect(QuarterTurn(nearest: 0.05, toleranceDegrees: -8) == nil)
}
