import CoreGraphics

public struct PageGeometry: Equatable, Sendable {
    public let contentWidth: CGFloat
    public let pageHeight: CGFloat
    public let orientation: PageOrientation

    public static let aspectRatioRange: ClosedRange<Double> = 0.5...3.0
    public static let a4 = PageGeometry(
        portraitAspectRatio: PageLayout.a4AspectRatio,
        orientation: .portrait
    )
    public static let a4Landscape = PageGeometry(
        portraitAspectRatio: PageLayout.a4AspectRatio,
        orientation: .landscape
    )

    public init(
        portraitAspectRatio: Double,
        orientation: PageOrientation = .portrait
    ) {
        let portraitWidth = PageLayout.portraitContentWidth
        let uprightHeight = portraitWidth * CGFloat(
            Self.clampedAspectRatio(portraitAspectRatio)
        )
        self.orientation = orientation
        switch orientation {
        case .portrait:
            contentWidth = portraitWidth
            pageHeight = uprightHeight
        case .landscape:
            contentWidth = uprightHeight
            pageHeight = portraitWidth
        }
    }

    public static func clampedAspectRatio(_ value: Double) -> Double {
        min(
            max(value, aspectRatioRange.lowerBound),
            aspectRatioRange.upperBound
        )
    }

    /// The orientation-independent upright page shape persisted by `Note`.
    public var portraitAspectRatio: Double {
        switch orientation {
        case .portrait:
            Double(pageHeight / contentWidth)
        case .landscape:
            Double(contentWidth / pageHeight)
        }
    }

    /// The actual height-to-width ratio after applying the page orientation.
    public var aspectRatio: Double {
        Double(pageHeight / contentWidth)
    }

    /// Returns the content-space rectangle of the zero-based page at `index`.
    public func pageRect(index: Int) -> CGRect {
        CGRect(
            x: 0,
            y: CGFloat(index) * pageHeight,
            width: contentWidth,
            height: pageHeight
        )
    }

    /// Aspect-fit rect for a source page of `size`, centered in band `pageIndex`'s page rect.
    public func fittedRect(forSourcePageSize size: CGSize, pageIndex: Int) -> CGRect {
        let pageRect = pageRect(index: pageIndex)
        guard size.width > 0, size.height > 0 else { return pageRect }

        let scale = min(pageRect.width / size.width, pageRect.height / size.height)
        let fittedSize = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: pageRect.midX - fittedSize.width / 2,
            y: pageRect.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    /// Returns the total scrollable height for `pageCount` pages.
    public func contentHeight(pageCount: Int) -> CGFloat {
        CGFloat(pageCount) * pageHeight
    }

    /// Returns the number of pages to display: the filled pages plus one always-blank page ahead.
    public func pageCount(forContentBottom bottom: CGFloat) -> Int {
        pageCount(forContentBottom: bottom, minimumFilledPages: 0)
    }

    /// Pages-aware count: filled is the greater of `minimumFilledPages` and the
    /// ink-derived filled count, with the same trailing-blank rule as `pageCount(forContentBottom:)`.
    public func pageCount(
        forContentBottom bottom: CGFloat,
        minimumFilledPages: Int
    ) -> Int {
        exportPageCount(
            forContentBottom: bottom,
            minimumFilledPages: minimumFilledPages
        ) + 1
    }

    /// Returns the number of non-blank pages to export for content extending to `bottom`.
    public func exportPageCount(forContentBottom bottom: CGFloat) -> Int {
        exportPageCount(forContentBottom: bottom, minimumFilledPages: 0)
    }

    /// Returns the pages-aware number of non-blank pages to export.
    public func exportPageCount(
        forContentBottom bottom: CGFloat,
        minimumFilledPages: Int
    ) -> Int {
        let inkDerivedFilledCount = bottom > 0
            ? Int((bottom / pageHeight).rounded(.up))
            : 0
        return max(1, max(minimumFilledPages, inkDerivedFilledCount))
    }

    /// Returns the page containing content-space `y`, clamped to the available pages.
    public func pageIndex(forContentY y: CGFloat, pageCount: Int) -> Int {
        let clampedPageCount = max(1, pageCount)
        guard y > 0 else { return 0 }

        let index = Int((y / pageHeight).rounded(.down))
        return min(index, clampedPageCount - 1)
    }

    public var pdfPageSize: CGSize {
        let pointsPerContentPoint = 595.2 / PageLayout.portraitContentWidth
        switch orientation {
        case .portrait:
            let width = contentWidth * pointsPerContentPoint
            return CGSize(
                width: width,
                height: width * CGFloat(portraitAspectRatio)
            )
        case .landscape:
            let height = pageHeight * pointsPerContentPoint
            return CGSize(
                width: height * CGFloat(portraitAspectRatio),
                height: height
            )
        }
    }

    public var rasterPageSizePixels: CGSize {
        CGSize(
            width: (contentWidth * 2).rounded(),
            height: (pageHeight * 2).rounded()
        )
    }
}
