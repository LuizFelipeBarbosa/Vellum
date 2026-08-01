import CoreGraphics
import Testing
@testable import VellumCore

private let portraitContentWidth = PageLayout.portraitContentWidth

@Test("Page dimensions use the A4 aspect ratio")
func pageDimensionsUseA4AspectRatio() {
    #expect(PageLayout.portraitContentWidth == 768)
    #expect(PageLayout.a4AspectRatio == 841.8 / 595.2)
    #expect(
        PageGeometry.a4.pageHeight
            == PageLayout.portraitContentWidth * CGFloat(PageLayout.a4AspectRatio)
    )
    #expect(PageGeometry.a4.pdfPageSize == CGSize(width: 595.2, height: 841.8))
    #expect(PageGeometry.a4.rasterPageSizePixels == CGSize(width: 1_536, height: 2_172))
}

@Test("Page rectangles are stacked in content space")
func pageRectanglesAreStackedInContentSpace() {
    for index in 0...3 {
        let rect = PageGeometry.a4.pageRect(index: index)

        #expect(rect.origin.x == 0)
        #expect(rect.origin.y == CGFloat(index) * PageGeometry.a4.pageHeight)
        #expect(rect.width == PageLayout.portraitContentWidth)
        #expect(rect.height == PageGeometry.a4.pageHeight)
    }
}

@Test("A portrait source page fits the band width and stays vertically centered")
func portraitSourcePageFitsBandWidth() {
    let sourceSize = CGSize(width: 600, height: 800)
    let fitted = PageGeometry.a4.fittedRect(forSourcePageSize: sourceSize, pageIndex: 0)
    let expectedHeight = sourceSize.height * PageLayout.portraitContentWidth / sourceSize.width

    #expect(fitted.minX == 0)
    #expect(fitted.width == PageLayout.portraitContentWidth)
    #expect(fitted.height == expectedHeight)
    #expect(fitted.midY == PageGeometry.a4.pageRect(index: 0).midY)
}

@Test("A landscape source page is vertically letterboxed and centered")
func landscapeSourcePageIsVerticallyLetterboxed() {
    let sourceSize = CGSize(width: 1_200, height: 600)
    let fitted = PageGeometry.a4.fittedRect(forSourcePageSize: sourceSize, pageIndex: 0)

    #expect(fitted.minX == 0)
    #expect(fitted.width == PageLayout.portraitContentWidth)
    #expect(fitted.height == 384)
    #expect(fitted.midY == PageGeometry.a4.pageRect(index: 0).midY)
}

@Test("A source matching the content-area aspect ratio fills the page rect")
func matchingAspectRatioFillsPageRect() {
    let sourceSize = CGSize(
        width: PageLayout.portraitContentWidth,
        height: PageGeometry.a4.pageHeight
    )

    #expect(
        PageGeometry.a4.fittedRect(forSourcePageSize: sourceSize, pageIndex: 1)
            == PageGeometry.a4.pageRect(index: 1)
    )
}

@Test("Degenerate source sizes fall back to the full page rect")
func degenerateSourceSizesUseFullPageRect() {
    let expected = PageGeometry.a4.pageRect(index: 1)
    let sizes = [
        CGSize(width: 0, height: 100),
        CGSize(width: 100, height: 0),
        CGSize(width: -100, height: 100),
    ]

    for size in sizes {
        #expect(PageGeometry.a4.fittedRect(forSourcePageSize: size, pageIndex: 1) == expected)
    }
}

@Test("A fitted source page uses the requested band's content-space offset")
func fittedSourcePageUsesRequestedBandOffset() {
    let sourceSize = CGSize(width: 1_200, height: 600)
    let fitted = PageGeometry.a4.fittedRect(forSourcePageSize: sourceSize, pageIndex: 2)
    let pageRect = PageGeometry.a4.pageRect(index: 2)

    #expect(fitted.minX == pageRect.minX)
    #expect(fitted.width == pageRect.width)
    #expect(fitted.height == 384)
    #expect(fitted.midY == pageRect.midY)
}

@Test("Content height is the page count times page height")
func contentHeightMatchesPageCount() {
    for pageCount in [0, 1, 2, 3, 8] {
        #expect(
            PageGeometry.a4.contentHeight(pageCount: pageCount)
                == CGFloat(pageCount) * PageGeometry.a4.pageHeight
        )
    }
}

@Test("Display page count keeps one blank page ahead")
func displayPageCountKeepsOneBlankPageAhead() {
    let height = PageGeometry.a4.pageHeight
    let epsilon: CGFloat = 0.000_001

    #expect(PageGeometry.a4.pageCount(forContentBottom: 0) == 2)
    #expect(PageGeometry.a4.pageCount(forContentBottom: -height) == 2)
    #expect(PageGeometry.a4.pageCount(forContentBottom: 0.5 * height) == 2)
    #expect(PageGeometry.a4.pageCount(forContentBottom: height) == 2)
    #expect(PageGeometry.a4.pageCount(forContentBottom: height + epsilon) == 3)
    #expect(PageGeometry.a4.pageCount(forContentBottom: 1.5 * height) == 3)
    #expect(PageGeometry.a4.pageCount(forContentBottom: 2 * height + epsilon) == 4)
}

@Test("Export page count excludes the trailing growth page")
func exportPageCountExcludesTrailingGrowthPage() {
    let height = PageGeometry.a4.pageHeight
    let epsilon: CGFloat = 0.000_001

    #expect(PageGeometry.a4.exportPageCount(forContentBottom: 0) == 1)
    #expect(PageGeometry.a4.exportPageCount(forContentBottom: height) == 1)
    #expect(PageGeometry.a4.exportPageCount(forContentBottom: 2 * height + epsilon) == 3)
}

@Test("A zero minimum filled-page count preserves the existing count APIs")
func zeroMinimumFilledPageCountPreservesExistingBehavior() {
    let height = PageGeometry.a4.pageHeight
    let epsilon: CGFloat = 0.000_001

    for bottom in [-height, 0, 0.5 * height, height, height + epsilon, 2 * height + epsilon] {
        #expect(
            PageGeometry.a4.pageCount(forContentBottom: bottom, minimumFilledPages: 0)
                == PageGeometry.a4.pageCount(forContentBottom: bottom)
        )
        #expect(
            PageGeometry.a4.exportPageCount(forContentBottom: bottom, minimumFilledPages: 0)
                == PageGeometry.a4.exportPageCount(forContentBottom: bottom)
        )
    }
}

/// The filled-page count is the greater of the materialized minimum and the ink-derived
/// count, and the displayed count adds one trailing blank page on top of it.
@Test("Filled-page count takes the greater of the minimum and the ink bottom", arguments: [
    // (content bottom in pages, minimum filled pages, displayed pages, exported pages)
    (0.5, 3, 4, 3), // the minimum wins over a smaller ink-derived count
    (2.5, 2, 4, 3), // the ink-derived count wins over a smaller minimum
    (0.0, 4, 5, 4), // empty content still retains its materialized pages
])
func filledPageCountTakesTheGreaterOfMinimumAndInkBottom(
    bottomInPages: Double,
    minimumFilledPages: Int,
    displayedPages: Int,
    exportedPages: Int
) {
    let bottom = CGFloat(bottomInPages) * PageGeometry.a4.pageHeight

    #expect(
        PageGeometry.a4.pageCount(
            forContentBottom: bottom,
            minimumFilledPages: minimumFilledPages
        ) == displayedPages
    )
    #expect(
        PageGeometry.a4.exportPageCount(
            forContentBottom: bottom,
            minimumFilledPages: minimumFilledPages
        ) == exportedPages
    )
}

@Test("Page index is clamped to the available pages")
func pageIndexIsClampedToAvailablePages() {
    let height = PageGeometry.a4.pageHeight

    #expect(PageGeometry.a4.pageIndex(forContentY: -10, pageCount: 3) == 0)
    #expect(PageGeometry.a4.pageIndex(forContentY: 1.5 * height, pageCount: 3) == 1)
    #expect(PageGeometry.a4.pageIndex(forContentY: 4 * height, pageCount: 3) == 2)
    #expect(PageGeometry.a4.pageIndex(forContentY: height, pageCount: 0) == 0)
}

@Test("Viewport zoom bounds scale from the content width")
func viewportZoomBoundsScaleFromContentWidth() {
    // Fit-to-width for the 768pt portrait content width, and the 4x ceiling above it.
    // Every value is an exact binary fraction, so `==` is safe.
    let cases: [(width: CGFloat, fit: CGFloat, ceiling: CGFloat)] = [
        (744, 0.968_75, 3.875),
        (834, 1.085_937_5, 4.343_75),
        (1_194, 1.554_687_5, 6.218_75),
    ]

    for (width, fit, ceiling) in cases {
        #expect(
            PageLayout.minZoom(
                forViewportWidth: width,
                contentWidth: portraitContentWidth
            ) == fit
        )
        #expect(
            PageLayout.maxZoom(
                forViewportWidth: width,
                contentWidth: portraitContentWidth
            ) == ceiling
        )
    }

    #expect(PageLayout.minZoom(
        forViewportWidth: 0,
        contentWidth: portraitContentWidth
    ) == 1)
    #expect(PageLayout.maxZoom(
        forViewportWidth: 0,
        contentWidth: portraitContentWidth
    ) == 4)
    #expect(PageLayout.minZoom(
        forViewportWidth: -100,
        contentWidth: portraitContentWidth
    ) == 1)
    #expect(PageLayout.maxZoom(
        forViewportWidth: -100,
        contentWidth: portraitContentWidth
    ) == 4)
}

@Test("Ended zoom scales snap to fit within the fit-relative band")
func endedZoomScalesSnapToFitWithinBand() {
    for width: CGFloat in [768, 1_024] {
        let fit = PageLayout.minZoom(
            forViewportWidth: width,
            contentWidth: portraitContentWidth
        )

        #expect(PageLayout.snapTargetZoom(
            forEndedZoomScale: fit,
            viewportWidth: width,
            contentWidth: portraitContentWidth
        ) == fit)
        #expect(
            PageLayout.snapTargetZoom(
                forEndedZoomScale: 0.95 * fit,
                viewportWidth: width,
                contentWidth: portraitContentWidth
            ) == fit
        )
        #expect(
            PageLayout.snapTargetZoom(
                forEndedZoomScale: 1.05 * fit,
                viewportWidth: width,
                contentWidth: portraitContentWidth
            ) == fit
        )
        #expect(
            PageLayout.snapTargetZoom(
                forEndedZoomScale: 1.09 * fit,
                viewportWidth: width,
                contentWidth: portraitContentWidth
            ) == fit
        )
        #expect(
            PageLayout.snapTargetZoom(
                forEndedZoomScale: 1.11 * fit,
                viewportWidth: width,
                contentWidth: portraitContentWidth
            ) == nil
        )
        #expect(
            PageLayout.snapTargetZoom(
                forEndedZoomScale: 0.89 * fit,
                viewportWidth: width,
                contentWidth: portraitContentWidth
            ) == nil
        )
        #expect(
            PageLayout.snapTargetZoom(
                forEndedZoomScale: 0.5 * fit,
                viewportWidth: width,
                contentWidth: portraitContentWidth
            ) == nil
        )
        #expect(
            PageLayout.snapTargetZoom(
                forEndedZoomScale: 0.25 * fit,
                viewportWidth: width,
                contentWidth: portraitContentWidth
            ) == nil
        )
    }

    // Exact band boundaries, checked where fit == 1 so the ratios are float-exact.
    #expect(
        PageLayout.snapTargetZoom(
            forEndedZoomScale: PageLayout.snapToFitLowerRatio,
            viewportWidth: 768,
            contentWidth: portraitContentWidth
        ) == 1
    )
    #expect(
        PageLayout.snapTargetZoom(
            forEndedZoomScale: PageLayout.snapToFitUpperRatio,
            viewportWidth: 768,
            contentWidth: portraitContentWidth
        ) == 1
    )

    #expect(PageLayout.snapTargetZoom(
        forEndedZoomScale: 1,
        viewportWidth: 0,
        contentWidth: portraitContentWidth
    ) == nil)
    #expect(PageLayout.snapTargetZoom(
        forEndedZoomScale: -1,
        viewportWidth: 768,
        contentWidth: portraitContentWidth
    ) == nil)
}

@Test("Ended zoom scales settle inside logical bounds")
func endedZoomScalesSettleInsideLogicalBounds() {
    let overviewFloor = PageLayout.overviewMinZoom(
        forViewportWidth: 768,
        contentWidth: portraitContentWidth
    )
    let maximum = PageLayout.maxZoom(
        forViewportWidth: 768,
        contentWidth: portraitContentWidth
    )

    #expect(settleTargetZoom(0.2) == overviewFloor)
    #expect(settleTargetZoom(0.125) == overviewFloor)
    #expect(settleTargetZoom(4.5) == maximum)
    #expect(settleTargetZoom(5) == maximum)
    #expect(settleTargetZoom(0.25) == nil)
    #expect(settleTargetZoom(0.5) == nil)
    #expect(settleTargetZoom(0.95) == 1)
    #expect(settleTargetZoom(2) == nil)
    #expect(settleTargetZoom(4) == nil)

    #expect(settleTargetZoom(1, viewportWidth: 0) == nil)
    #expect(settleTargetZoom(1, viewportWidth: -768) == nil)
    #expect(settleTargetZoom(0) == nil)
    #expect(settleTargetZoom(-1) == nil)

    let secondWidth: CGFloat = 1_024
    let secondFit = PageLayout.minZoom(
        forViewportWidth: secondWidth,
        contentWidth: portraitContentWidth
    )
    #expect(
        PageLayout.settleTargetZoom(
            forEndedZoomScale: 0.2 * secondFit,
            viewportWidth: secondWidth,
            contentWidth: portraitContentWidth
        ) == PageLayout.overviewMinZoom(
            forViewportWidth: secondWidth,
            contentWidth: portraitContentWidth
        )
    )
    #expect(
        PageLayout.settleTargetZoom(
            forEndedZoomScale: 4.5 * secondFit,
            viewportWidth: secondWidth,
            contentWidth: portraitContentWidth
        ) == PageLayout.maxZoom(
            forViewportWidth: secondWidth,
            contentWidth: portraitContentWidth
        )
    )
}

private func settleTargetZoom(
    _ scale: CGFloat,
    viewportWidth: CGFloat = 768
) -> CGFloat? {
    PageLayout.settleTargetZoom(
        forEndedZoomScale: scale,
        viewportWidth: viewportWidth,
        contentWidth: portraitContentWidth
    )
}

@Test("Anchored zoom offset keeps the visible center within the default range")
func anchoredZoomOffsetKeepsVisibleCenterWithinDefaultRange() {
    #expect(
        PageLayout.anchoredOffsetY(
            visibleCenterContentY: 1_000,
            scale: 1,
            viewportHeight: 800,
            contentHeight: 3_000
        ) == 600
    )
    #expect(
        PageLayout.anchoredOffsetY(
            visibleCenterContentY: 100,
            scale: 1,
            viewportHeight: 800,
            contentHeight: 3_000
        ) == 0
    )
    #expect(
        PageLayout.anchoredOffsetY(
            visibleCenterContentY: 2_900,
            scale: 1,
            viewportHeight: 800,
            contentHeight: 3_000
        ) == 2_200
    )
    #expect(
        PageLayout.anchoredOffsetY(
            visibleCenterContentY: 900,
            scale: 0.5,
            viewportHeight: 800,
            contentHeight: 1_000
        ) == 0
    )
}

@Test("Anchored zoom offset respects a custom minimum")
func anchoredZoomOffsetRespectsCustomMinimum() {
    #expect(
        PageLayout.anchoredOffsetY(
            visibleCenterContentY: 300,
            scale: 1,
            viewportHeight: 800,
            contentHeight: 3_000,
            minimumOffsetY: -120
        ) == -100
    )
    #expect(
        PageLayout.anchoredOffsetY(
            visibleCenterContentY: 100,
            scale: 1,
            viewportHeight: 800,
            contentHeight: 3_000,
            minimumOffsetY: -120
        ) == -120
    )
    #expect(
        PageLayout.anchoredOffsetY(
            visibleCenterContentY: 2_900,
            scale: 1,
            viewportHeight: 800,
            contentHeight: 3_000,
            minimumOffsetY: -120
        ) == 2_200
    )
}

/// The zoom-out floor the multi-page overview relies on: a quarter of fit-to-width.
/// Expectations are pinned to numbers rather than re-derived from `overviewZoomFactor`,
/// so moving that constant has to be a deliberate, visible change here.
/// Degenerate widths fall back to fit == 1, leaving the bare factor.
@Test("Overview minimum zoom is a quarter of fit-to-width", arguments: [
    (CGFloat(744), CGFloat(0.242_187_5)),
    (CGFloat(834), CGFloat(0.271_484_375)),
    (CGFloat(1_194), CGFloat(0.388_671_875)),
    (CGFloat(0), CGFloat(0.25)),
    (CGFloat(-100), CGFloat(0.25)),
])
func overviewMinimumZoomIsFractionOfFitToWidth(width: CGFloat, expected: CGFloat) {
    #expect(
        PageLayout.overviewMinZoom(
            forViewportWidth: width,
            contentWidth: portraitContentWidth
        ) == expected
    )
}
