@testable import Vellum
import XCTest

@MainActor
final class ToolWidthLevelsTests: XCTestCase {
    private let widthRanges: [ClosedRange<Double>] = [
        1...12,
        1...16,
        6...30,
        8...60,
    ]

    func testEndpointsMapToRangeBounds() {
        for range in widthRanges {
            XCTAssertEqual(
                ToolWidthLevels.width(forLevel: 1, in: range),
                range.lowerBound
            )
            XCTAssertEqual(
                ToolWidthLevels.width(forLevel: 10, in: range),
                range.upperBound
            )
        }
    }

    func testEveryLevelRoundTripsForEachWidthRange() {
        for range in widthRanges {
            for level in ToolWidthLevels.levelRange {
                let width = ToolWidthLevels.width(forLevel: level, in: range)

                XCTAssertEqual(
                    ToolWidthLevels.level(forWidth: width, in: range),
                    level
                )
            }
        }
    }

    func testWidthsBetweenAdjacentLevelsMapToNearestLevel() {
        for range in widthRanges {
            let lowerLevel = 4
            let upperLevel = 5
            let lowerWidth = ToolWidthLevels.width(forLevel: lowerLevel, in: range)
            let upperWidth = ToolWidthLevels.width(forLevel: upperLevel, in: range)
            let distance = upperWidth - lowerWidth

            XCTAssertEqual(
                ToolWidthLevels.level(
                    forWidth: lowerWidth + (distance * 0.25),
                    in: range
                ),
                lowerLevel
            )
            XCTAssertEqual(
                ToolWidthLevels.level(
                    forWidth: lowerWidth + (distance * 0.75),
                    in: range
                ),
                upperLevel
            )
        }
    }

    func testLevelsAndWidthsClampToRangeEndpoints() {
        for range in widthRanges {
            XCTAssertEqual(
                ToolWidthLevels.width(forLevel: 0, in: range),
                range.lowerBound
            )
            XCTAssertEqual(
                ToolWidthLevels.width(forLevel: 11, in: range),
                range.upperBound
            )
            XCTAssertEqual(
                ToolWidthLevels.level(forWidth: range.lowerBound - 1, in: range),
                1
            )
            XCTAssertEqual(
                ToolWidthLevels.level(forWidth: range.upperBound + 1, in: range),
                10
            )
        }
    }
}
