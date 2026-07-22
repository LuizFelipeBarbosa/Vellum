enum ToolWidthLevels {
    static let levelRange: ClosedRange<Int> = 1...10

    /// Width in points for a level, linearly interpolated across `range`.
    /// Level is clamped to 1...10. Level 1 -> range.lowerBound, 10 -> range.upperBound.
    static func width(forLevel level: Int, in range: ClosedRange<Double>) -> Double {
        let clampedLevel = min(max(level, levelRange.lowerBound), levelRange.upperBound)

        if clampedLevel == levelRange.lowerBound {
            return range.lowerBound
        }
        if clampedLevel == levelRange.upperBound {
            return range.upperBound
        }

        let levelSpan = levelRange.upperBound - levelRange.lowerBound
        let levelOffset = clampedLevel - levelRange.lowerBound
        let fraction = Double(levelOffset) / Double(levelSpan)
        return range.lowerBound + ((range.upperBound - range.lowerBound) * fraction)
    }

    /// Nearest level (1...10) for a width in points; out-of-range widths clamp.
    static func level(forWidth width: Double, in range: ClosedRange<Double>) -> Int {
        guard range.lowerBound < range.upperBound else {
            return levelRange.lowerBound
        }
        if width <= range.lowerBound {
            return levelRange.lowerBound
        }
        if width >= range.upperBound {
            return levelRange.upperBound
        }

        let fraction = (width - range.lowerBound) / (range.upperBound - range.lowerBound)
        let levelSpan = levelRange.upperBound - levelRange.lowerBound
        let levelOffset = Int((fraction * Double(levelSpan)).rounded())
        return levelRange.lowerBound + levelOffset
    }
}
