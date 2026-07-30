import CoreGraphics
import Foundation

public enum SplitDropTarget: Equatable, Sendable {
    case insertBetween(index: Int)
    case existingPane(index: Int)
}

public enum SplitLayoutPolicy {
    public static let minPaneWidth: CGFloat = 320
    public static let dividerHitWidth: CGFloat = 24
    public static let edgeZoneFraction: CGFloat = 0.25

    /// Keeping pane shares normalized makes the layout independent of container size.
    public static func normalized(_ fractions: [CGFloat]) -> [CGFloat] {
        guard !fractions.isEmpty else { return [] }

        let nonnegativeFractions = fractions.map { fraction in
            fraction.isFinite ? max(0, fraction) : 0
        }
        guard let largestFraction = nonnegativeFractions.max(),
              largestFraction > 0 else {
            return equalFractions(count: fractions.count)
        }

        let scaledFractions = nonnegativeFractions.map { $0 / largestFraction }
        let scaledSum = scaledFractions.reduce(0, +)
        return scaledFractions.map { $0 / scaledSum }
    }

    /// The pane limit prevents a split from promising widths the container cannot provide.
    public static func maxPaneCount(forContainerWidth width: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 1 }

        let fittingPaneCount = width / minPaneWidth
        guard fittingPaneCount < CGFloat(Int.max) else { return Int.max }
        return max(1, Int(fittingPaneCount))
    }

    /// Resolving normalized shares at the boundary keeps invalid container geometry from spreading.
    public static func paneWidths(
        fractions: [CGFloat],
        containerWidth: CGFloat
    ) -> [CGFloat] {
        let width = usableWidth(containerWidth)
        return normalized(fractions).map { $0 * width }
    }

    /// Enforcing the shared minimum keeps every feasible pane usable without changing total width.
    public static func clampedToMinWidth(
        fractions: [CGFloat],
        containerWidth: CGFloat
    ) -> [CGFloat] {
        let normalizedFractions = normalized(fractions)
        guard !normalizedFractions.isEmpty else { return [] }

        let width = usableWidth(containerWidth)
        let paneCount = normalizedFractions.count
        guard CGFloat(paneCount) * minPaneWidth <= width else {
            return equalFractions(count: paneCount)
        }

        let minimumFraction = minPaneWidth / width
        var result = normalizedFractions
        var deficit: CGFloat = 0
        var availableExcess: CGFloat = 0

        for (index, fraction) in normalizedFractions.enumerated() {
            if fraction < minimumFraction {
                deficit += minimumFraction - fraction
                result[index] = minimumFraction
            } else {
                availableExcess += fraction - minimumFraction
            }
        }

        guard deficit > 0, availableExcess > 0 else {
            return normalizedFractions
        }

        for (index, fraction) in normalizedFractions.enumerated()
        where fraction > minimumFraction {
            let excess = fraction - minimumFraction
            result[index] -= deficit * excess / availableExcess
        }

        return normalized(result)
    }

    /// Moving one divider transfers width only between its neighbors while preserving their total.
    public static func fractionsResizing(
        _ startFractions: [CGFloat],
        dividerIndex: Int,
        byTranslation dx: CGFloat,
        containerWidth: CGFloat
    ) -> [CGFloat] {
        guard startFractions.count >= 2,
              dividerIndex >= 0,
              dividerIndex < startFractions.count - 1 else {
            return startFractions
        }

        let width = usableWidth(containerWidth)
        guard width > 0, dx.isFinite else { return startFractions }

        let leftFraction = startFractions[dividerIndex]
        let rightFraction = startFractions[dividerIndex + 1]
        let minimumFraction = minPaneWidth / width
        guard leftFraction + rightFraction >= 2 * minimumFraction else {
            return startFractions
        }

        let proposedChange = dx / width
        let minimumChange = minimumFraction - leftFraction
        let maximumChange = rightFraction - minimumFraction
        let change = min(max(proposedChange, minimumChange), maximumChange)

        var result = startFractions
        result[dividerIndex] = leftFraction + change
        result[dividerIndex + 1] = rightFraction - change
        return result
    }

    /// Edge zones favor insertion, with exact pane and zone boundaries tied toward insertion slots.
    public static func dropTarget(
        forX x: CGFloat,
        fractions: [CGFloat],
        containerWidth: CGFloat
    ) -> SplitDropTarget {
        guard !fractions.isEmpty else { return .insertBetween(index: 0) }

        let width = usableWidth(containerWidth)
        guard !x.isNaN else { return .insertBetween(index: 0) }
        if x <= 0 {
            return .insertBetween(index: 0)
        }
        if x >= width {
            return .insertBetween(index: fractions.count)
        }

        let widths = paneWidths(fractions: fractions, containerWidth: width)
        var paneStartX: CGFloat = 0

        for (index, paneWidth) in widths.enumerated() {
            let paneEndX = paneStartX + paneWidth
            let leftEdgeZoneEnd = paneStartX + paneWidth * edgeZoneFraction
            let rightEdgeZoneStart = paneEndX - paneWidth * edgeZoneFraction

            if x <= leftEdgeZoneEnd {
                return .insertBetween(index: index)
            }
            if x < rightEdgeZoneStart {
                return .existingPane(index: index)
            }
            if x <= paneEndX {
                return .insertBetween(index: index + 1)
            }

            paneStartX = paneEndX
        }

        return .insertBetween(index: fractions.count)
    }

    /// Giving a new pane one equal-count share preserves the relative sizes of existing panes.
    public static func fractionsInserting(
        at index: Int,
        into fractions: [CGFloat]
    ) -> [CGFloat] {
        guard !fractions.isEmpty else { return [1] }

        let paneCount = fractions.count
        let newPaneFraction = 1 / CGFloat(paneCount + 1)
        let existingScale = CGFloat(paneCount) / CGFloat(paneCount + 1)
        var result = normalized(fractions).map { $0 * existingScale }
        let insertionIndex = min(max(index, 0), paneCount)
        result.insert(newPaneFraction, at: insertionIndex)
        return result
    }

    /// Renormalizing survivors redistributes a removed pane in proportion to their existing shares.
    public static func fractionsRemoving(
        at index: Int,
        from fractions: [CGFloat]
    ) -> [CGFloat] {
        guard fractions.indices.contains(index) else { return fractions }
        guard fractions.count > 1 else { return [] }

        var survivors = fractions
        survivors.remove(at: index)
        return normalized(survivors)
    }

    private static func usableWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 0 }
        return width
    }

    private static func equalFractions(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        return Array(repeating: 1 / CGFloat(count), count: count)
    }
}
