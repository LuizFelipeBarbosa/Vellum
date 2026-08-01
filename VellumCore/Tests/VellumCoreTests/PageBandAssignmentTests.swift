import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import VellumCore

@Test("Band assignment uses the anchor's containing page")
func bandAssignmentUsesContainingPage() {
    let geometry = PageGeometry.a4
    for index in 0...2 {
        let centerY = (CGFloat(index) + 0.5) * geometry.pageHeight

        #expect(
            PageBandAssignment.band(
                forAnchorY: centerY,
                bandCount: 3,
                geometry: geometry
            ) == index
        )
    }
}

@Test("An anchor on a page boundary belongs to the next band")
func boundaryAnchorBelongsToNextBand() {
    #expect(
        PageBandAssignment.band(
            forAnchorY: PageGeometry.a4.pageHeight,
            bandCount: 3,
            geometry: .a4
        ) == 1
    )
}

@Test("Negative anchors clamp to the first band")
func negativeAnchorClampsToFirstBand() {
    #expect(PageBandAssignment.band(forAnchorY: -100, bandCount: 3, geometry: .a4) == 0)
}

@Test("Anchors beyond the available range clamp to the last band")
func anchorBeyondRangeClampsToLastBand() {
    #expect(
        PageBandAssignment.band(
            forAnchorY: 10 * PageGeometry.a4.pageHeight,
            bandCount: 3,
            geometry: .a4
        ) == 2
    )
}

@Test("A nonpositive band count always resolves to band zero")
func nonpositiveBandCountResolvesToZero() {
    #expect(
        PageBandAssignment.band(
            forAnchorY: PageGeometry.a4.pageHeight,
            bandCount: 0,
            geometry: .a4
        ) == 0
    )
    #expect(
        PageBandAssignment.band(
            forAnchorY: -PageGeometry.a4.pageHeight,
            bandCount: -2,
            geometry: .a4
        ) == 0
    )
}

/// The hand-picked moves, side by side so the shape of each kind of move stays readable.
/// `randomizedPermutationsMatchArrayMove` below covers the same ground against the stdlib
/// `Array.move` as an independent oracle; these pin the cases that were written by hand.
@Test("The permutation reindexes the moved items and everything they pass", arguments: [
    // (item count, indices moved, destination offset, resulting permutation)
    (4, IndexSet(integer: 1), 4, [0, 3, 1, 2]), // one item forward
    (4, IndexSet(integer: 3), 1, [0, 2, 3, 1]), // one item backward
    (4, IndexSet([1, 3]), 0, [2, 0, 3, 1]), // multiple items together
    (5, IndexSet([0, 2]), 5, [3, 0, 4, 1, 2]), // multiple items to the end
    (5, IndexSet([1, 2]), 3, [0, 1, 2, 3, 4]), // onto the source's own post-removal slot
])
func permutationReindexesMovedItems(
    count: Int,
    moving: IndexSet,
    to destination: Int,
    expected: [Int]
) {
    #expect(
        PageBandAssignment.permutation(
            count: count,
            moving: moving,
            to: destination
        ) == expected
    )
}

@Test("Randomized permutations match the real Array move operation")
func randomizedPermutationsMatchArrayMove() {
    var generator = DeterministicGenerator(state: 0xC0FFEE)

    for count in 4...8 {
        for _ in 0..<30 {
            var source = IndexSet()
            for index in 0..<count where generator.next() % 3 == 0 {
                source.insert(index)
            }
            if source.isEmpty {
                source.insert(Int(generator.next() % UInt64(count)))
            }
            let destination = Int(generator.next() % UInt64(count + 1))

            var expected = Array(0..<count)
            expected.move(fromOffsets: source, toOffset: destination)

            let permutation = PageBandAssignment.permutation(
                count: count,
                moving: source,
                to: destination
            )
            var scattered = Array(repeating: -1, count: count)
            for oldIndex in 0..<count {
                scattered[permutation[oldIndex]] = oldIndex
            }

            #expect(scattered == expected)
        }
    }
}

private struct DeterministicGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
