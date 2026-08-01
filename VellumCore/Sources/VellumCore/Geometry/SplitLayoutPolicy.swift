import CoreGraphics
import Foundation

public enum SplitLayoutPolicy {
    /// Keeping pane shares normalized makes the layout independent of container size.
    public static func normalized(_ fractions: [CGFloat]) -> [CGFloat] {
        guard !fractions.isEmpty else { return [] }

        let nonnegativeFractions = fractions.map(\.nonnegativeFinite)
        guard let largestFraction = nonnegativeFractions.max(),
              largestFraction > 0 else {
            return equalFractions(count: fractions.count)
        }

        let scaledFractions = nonnegativeFractions.map { $0 / largestFraction }
        let scaledSum = scaledFractions.reduce(0, +)
        return scaledFractions.map { $0 / scaledSum }
    }

    /// An axis-specific limit prevents a split from promising lengths the container cannot provide.
    public static func maxCount(
        axisLength: CGFloat,
        minLength: CGFloat
    ) -> Int {
        guard axisLength.isFinite, axisLength > 0,
              minLength.isFinite, minLength > 0 else {
            return 1
        }

        let fittingPaneCount = axisLength / minLength
        guard fittingPaneCount < CGFloat(Int.max) else { return Int.max }
        return max(1, Int(fittingPaneCount))
    }

    /// Resolving normalized shares on either axis contains invalid geometry at the boundary.
    public static func lengths(
        fractions: [CGFloat],
        axisLength: CGFloat
    ) -> [CGFloat] {
        let length = usableLength(axisLength)
        return normalized(fractions).map { $0 * length }
    }

    /// Enforcing an axis-specific minimum preserves usable panes without changing their total share.
    public static func clampedToMinLength(
        fractions: [CGFloat],
        axisLength: CGFloat,
        minLength: CGFloat
    ) -> [CGFloat] {
        let normalizedFractions = normalized(fractions)
        guard !normalizedFractions.isEmpty else { return [] }
        guard minLength.isFinite, minLength > 0 else {
            return normalizedFractions
        }

        let length = usableLength(axisLength)
        let paneCount = normalizedFractions.count
        guard CGFloat(paneCount) * minLength <= length else {
            return equalFractions(count: paneCount)
        }

        let minimumFraction = minLength / length
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

    /// Moving one divider on either axis transfers space only between its neighboring panes.
    public static func fractionsResizing(
        _ startFractions: [CGFloat],
        dividerIndex: Int,
        byTranslation delta: CGFloat,
        axisLength: CGFloat,
        minLength: CGFloat
    ) -> [CGFloat] {
        guard startFractions.count >= 2,
              dividerIndex >= 0,
              dividerIndex < startFractions.count - 1 else {
            return startFractions
        }

        let length = usableLength(axisLength)
        guard length > 0, delta.isFinite,
              minLength.isFinite, minLength > 0 else {
            return startFractions
        }

        let leftFraction = startFractions[dividerIndex]
        let rightFraction = startFractions[dividerIndex + 1]
        let minimumFraction = minLength / length
        guard leftFraction + rightFraction >= 2 * minimumFraction else {
            return startFractions
        }

        let proposedChange = delta / length
        let minimumChange = minimumFraction - leftFraction
        let maximumChange = rightFraction - minimumFraction
        let change = min(max(proposedChange, minimumChange), maximumChange)

        var result = startFractions
        result[dividerIndex] = leftFraction + change
        result[dividerIndex + 1] = rightFraction - change
        return result
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

    private static func usableLength(_ length: CGFloat) -> CGFloat {
        guard length.isFinite, length > 0 else { return 0 }
        return length
    }

    private static func equalFractions(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        return Array(repeating: 1 / CGFloat(count), count: count)
    }
}
