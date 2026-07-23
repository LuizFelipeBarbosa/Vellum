import CoreGraphics
import Foundation

public enum PageBandAssignment {
    /// Band index for a content-space anchor Y, clamped to the available bands.
    public static func band(
        forAnchorY y: CGFloat,
        bandCount: Int,
        geometry: PageGeometry
    ) -> Int {
        guard bandCount > 0 else { return 0 }

        let unclampedBand = floor(y / geometry.pageHeight)
        guard !unclampedBand.isNaN else { return 0 }
        guard unclampedBand.isFinite else {
            return unclampedBand.sign == .minus ? 0 : bandCount - 1
        }
        guard unclampedBand > 0 else { return 0 }
        guard unclampedBand < CGFloat(bandCount - 1) else { return bandCount - 1 }
        return Int(unclampedBand)
    }

    /// Old-index to new-index mapping using SwiftUI List move semantics.
    public static func permutation(
        count: Int,
        moving source: IndexSet,
        to destination: Int
    ) -> [Int] {
        precondition(count >= 0)
        precondition(source.allSatisfy { $0 >= 0 && $0 < count })
        precondition(destination >= 0 && destination <= count)

        var reorderedOldIndices = Array(0..<count)
        let movedOldIndices = source.map { reorderedOldIndices[$0] }
        for offset in source.reversed() {
            reorderedOldIndices.remove(at: offset)
        }
        let removedBeforeDestination = source.count(in: 0..<destination)
        let insertionIndex = destination - removedBeforeDestination
        reorderedOldIndices.insert(contentsOf: movedOldIndices, at: insertionIndex)

        var permutation = Array(repeating: 0, count: count)
        for (newIndex, oldIndex) in reorderedOldIndices.enumerated() {
            permutation[oldIndex] = newIndex
        }
        return permutation
    }
}
