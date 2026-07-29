extension Array where Element == CanvasElement {
    /// If no element in the array carries an explicit `layerPlacement`, this is a legacy
    /// array — stable-sort it into the historical band order: images first (rank 0),
    /// shapes/unknown next (rank 1), text last (rank 2), preserving original relative
    /// order within each rank. If ANY element has a non-nil `layerPlacement`, the array
    /// is returned unchanged (already-migrated arrays are never re-banded).
    public func zOrderNormalized() -> [CanvasElement] {
        guard allSatisfy({ $0.layerPlacement == nil }) else { return self }

        let images = filter {
            if case .image = $0.content { return true }
            return false
        }
        let shapesAndUnknown = filter {
            switch $0.content {
            case .shape, .unknown:
                return true
            case .text, .image:
                return false
            }
        }
        let texts = filter {
            if case .text = $0.content { return true }
            return false
        }
        return images + shapesAndUnknown + texts
    }

    /// `zOrderNormalized()`, then a stable partition placing elements with
    /// `effectivePlacement == .belowInk` before elements with `effectivePlacement == .aboveInk`,
    /// preserving relative order within each partition. This is the paint order
    /// bottom-to-top; the page's ink drawing itself is painted between the two partitions
    /// (not represented in this array).
    public func sortedByEffectiveZ() -> [CanvasElement] {
        let normalized = zOrderNormalized()
        return normalized.filter { $0.effectivePlacement == .belowInk }
            + normalized.filter { $0.effectivePlacement == .aboveInk }
    }
}
