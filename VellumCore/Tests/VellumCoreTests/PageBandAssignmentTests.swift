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

@Test("The permutation moves one item forward")
func permutationMovesOneItemForward() {
    #expect(
        PageBandAssignment.permutation(
            count: 4,
            moving: IndexSet(integer: 1),
            to: 4
        ) == [0, 3, 1, 2]
    )
}

@Test("The permutation moves one item backward")
func permutationMovesOneItemBackward() {
    #expect(
        PageBandAssignment.permutation(
            count: 4,
            moving: IndexSet(integer: 3),
            to: 1
        ) == [0, 2, 3, 1]
    )
}

@Test("The permutation moves multiple indexed items together")
func permutationMovesMultipleItems() {
    #expect(
        PageBandAssignment.permutation(
            count: 4,
            moving: IndexSet([1, 3]),
            to: 0
        ) == [2, 0, 3, 1]
    )
}

@Test("The permutation supports moving multiple items to the end")
func permutationMovesMultipleItemsToEnd() {
    #expect(
        PageBandAssignment.permutation(
            count: 5,
            moving: IndexSet([0, 2]),
            to: 5
        ) == [3, 0, 4, 1, 2]
    )
}

@Test("A move onto the source's post-removal position is a no-op")
func permutationNoOpIsIdentity() {
    #expect(
        PageBandAssignment.permutation(
            count: 5,
            moving: IndexSet([1, 2]),
            to: 3
        ) == Array(0..<5)
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
