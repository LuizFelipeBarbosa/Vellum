import CoreGraphics

public enum PageBackgroundPattern {
    public struct AxisStride: Equatable, Sendable {
        public let start: CGFloat
        public let step: CGFloat
        public let count: Int

        public var values: [CGFloat] {
            guard count > 0 else { return [] }
            return (0..<count).map { start + CGFloat($0) * step }
        }
    }

    /// What `style` puts on `pageRect`, clipped to `visibleRect`, in CONTENT coordinates.
    /// Callers map to their own space and draw with their own API — that part legitimately
    /// differs (SwiftUI GraphicsContext vs CGContext, viewport transform vs preview downscale).
    public enum Marks: Equatable, Sendable {
        case none
        case dots(xs: AxisStride, ys: AxisStride)
        /// `columns` is non-nil only for `.grid`.
        case rules(rows: AxisStride, columns: AxisStride?)
    }

    public static func marks(
        style: PageBackgroundStyle,
        pageRect: CGRect,
        clippedTo visibleRect: CGRect
    ) -> Marks {
        switch style.kind {
        case .blank:
            return .none
        case .dots:
            return .dots(
                xs: dotXs(style: style, pageRect: pageRect, clippedTo: visibleRect),
                ys: dotYs(style: style, pageRect: pageRect, clippedTo: visibleRect)
            )
        case .ruled, .grid:
            return .rules(
                rows: ruleYs(style: style, pageRect: pageRect, clippedTo: visibleRect),
                columns: style.kind == .grid
                    ? gridXs(style: style, pageRect: pageRect, clippedTo: visibleRect)
                    : nil
            )
        }
    }

    public static func ruleYs(
        style: PageBackgroundStyle,
        pageRect: CGRect,
        clippedTo visibleRect: CGRect
    ) -> AxisStride {
        stride(
            style: style,
            pageRect: pageRect,
            visibleRect: visibleRect,
            axis: .vertical,
            firstIndex: 1,
            includesPageMaximum: false
        )
    }

    public static func gridXs(
        style: PageBackgroundStyle,
        pageRect: CGRect,
        clippedTo visibleRect: CGRect
    ) -> AxisStride {
        stride(
            style: style,
            pageRect: pageRect,
            visibleRect: visibleRect,
            axis: .horizontal,
            firstIndex: 1,
            includesPageMaximum: false
        )
    }

    public static func dotXs(
        style: PageBackgroundStyle,
        pageRect: CGRect,
        clippedTo visibleRect: CGRect
    ) -> AxisStride {
        stride(
            style: style,
            pageRect: pageRect,
            visibleRect: visibleRect,
            axis: .horizontal,
            firstIndex: 0,
            includesPageMaximum: true
        )
    }

    public static func dotYs(
        style: PageBackgroundStyle,
        pageRect: CGRect,
        clippedTo visibleRect: CGRect
    ) -> AxisStride {
        stride(
            style: style,
            pageRect: pageRect,
            visibleRect: visibleRect,
            axis: .vertical,
            firstIndex: 0,
            includesPageMaximum: true
        )
    }
}

private extension PageBackgroundPattern {
    enum Axis {
        case horizontal
        case vertical
    }

    static func stride(
        style: PageBackgroundStyle,
        pageRect: CGRect,
        visibleRect: CGRect,
        axis: Axis,
        firstIndex: Int,
        includesPageMaximum: Bool
    ) -> AxisStride {
        let step = CGFloat(PageBackgroundStyle.clampedSpacing(style.spacing))
        let intersection = pageRect.intersection(visibleRect)
        guard !intersection.isNull, !intersection.isEmpty else {
            return AxisStride(start: 0, step: step, count: 0)
        }

        let origin: CGFloat
        let pageMaximum: CGFloat
        let clippedMinimum: CGFloat
        let clippedMaximum: CGFloat
        switch axis {
        case .horizontal:
            origin = pageRect.minX
            pageMaximum = pageRect.maxX
            clippedMinimum = intersection.minX
            clippedMaximum = intersection.maxX
        case .vertical:
            origin = pageRect.minY
            pageMaximum = pageRect.maxY
            clippedMinimum = intersection.minY
            clippedMaximum = intersection.maxY
        }

        guard origin.isFinite,
              pageMaximum.isFinite,
              clippedMinimum.isFinite,
              clippedMaximum.isFinite,
              pageMaximum >= origin else {
            return AxisStride(start: 0, step: step, count: 0)
        }

        let pageIndexLimit: CGFloat
        if includesPageMaximum {
            pageIndexLimit = ((pageMaximum - origin) / step).rounded(.down)
        } else {
            pageIndexLimit = ((pageMaximum - origin) / step).rounded(.up) - 1
        }
        let clippedFirstIndex = ((clippedMinimum - origin) / step).rounded(.up)
        let clippedLastIndex = ((clippedMaximum - origin) / step).rounded(.down)

        guard pageIndexLimit >= 0,
              pageIndexLimit < CGFloat(Int.max),
              clippedFirstIndex >= 0,
              clippedFirstIndex < CGFloat(Int.max),
              clippedLastIndex >= 0,
              clippedLastIndex < CGFloat(Int.max) else {
            return AxisStride(start: 0, step: step, count: 0)
        }

        let lowerIndex = max(firstIndex, Int(clippedFirstIndex))
        let upperIndex = min(Int(pageIndexLimit), Int(clippedLastIndex))
        guard lowerIndex <= upperIndex else {
            return AxisStride(start: 0, step: step, count: 0)
        }

        return AxisStride(
            start: origin + CGFloat(lowerIndex) * step,
            step: step,
            count: upperIndex - lowerIndex + 1
        )
    }
}
