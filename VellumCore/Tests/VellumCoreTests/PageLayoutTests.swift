import CoreGraphics
import Testing
@testable import VellumCore

@Test("Page dimensions use the A4 aspect ratio")
func pageDimensionsUseA4AspectRatio() {
    #expect(PageLayout.contentWidth == 768)
    #expect(PageLayout.a4AspectRatio == 841.8 / 595.2)
    #expect(
        PageGeometry.a4.pageHeight
            == PageLayout.contentWidth * CGFloat(PageLayout.a4AspectRatio)
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
        #expect(rect.width == PageLayout.contentWidth)
        #expect(rect.height == PageGeometry.a4.pageHeight)
    }
}

@Test("A portrait source page fits the band width and stays vertically centered")
func portraitSourcePageFitsBandWidth() {
    let sourceSize = CGSize(width: 600, height: 800)
    let fitted = PageGeometry.a4.fittedRect(forSourcePageSize: sourceSize, pageIndex: 0)
    let expectedHeight = sourceSize.height * PageLayout.contentWidth / sourceSize.width

    #expect(fitted.minX == 0)
    #expect(fitted.width == PageLayout.contentWidth)
    #expect(fitted.height == expectedHeight)
    #expect(fitted.midY == PageGeometry.a4.pageRect(index: 0).midY)
}

@Test("A landscape source page is vertically letterboxed and centered")
func landscapeSourcePageIsVerticallyLetterboxed() {
    let sourceSize = CGSize(width: 1_200, height: 600)
    let fitted = PageGeometry.a4.fittedRect(forSourcePageSize: sourceSize, pageIndex: 0)

    #expect(fitted.minX == 0)
    #expect(fitted.width == PageLayout.contentWidth)
    #expect(fitted.height == 384)
    #expect(fitted.midY == PageGeometry.a4.pageRect(index: 0).midY)
}

@Test("A source matching the content-area aspect ratio fills the page rect")
func matchingAspectRatioFillsPageRect() {
    let sourceSize = CGSize(
        width: PageLayout.contentWidth,
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

@Test("The minimum filled-page count wins over a smaller ink-derived count")
func minimumFilledPageCountWins() {
    let bottom = 0.5 * PageGeometry.a4.pageHeight

    #expect(PageGeometry.a4.pageCount(forContentBottom: bottom, minimumFilledPages: 3) == 4)
    #expect(PageGeometry.a4.exportPageCount(forContentBottom: bottom, minimumFilledPages: 3) == 3)
}

@Test("The ink-derived count wins over a smaller minimum filled-page count")
func inkDerivedFilledPageCountWins() {
    let bottom = 2.5 * PageGeometry.a4.pageHeight

    #expect(PageGeometry.a4.pageCount(forContentBottom: bottom, minimumFilledPages: 2) == 4)
    #expect(PageGeometry.a4.exportPageCount(forContentBottom: bottom, minimumFilledPages: 2) == 3)
}

@Test("Empty content retains materialized pages plus one trailing blank page")
func emptyContentUsesMinimumFilledPageCount() {
    #expect(PageGeometry.a4.pageCount(forContentBottom: 0, minimumFilledPages: 4) == 5)
    #expect(PageGeometry.a4.exportPageCount(forContentBottom: 0, minimumFilledPages: 4) == 4)
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
    for width: CGFloat in [744, 834, 1_194] {
        let expectedMinimum = width / PageLayout.contentWidth

        #expect(PageLayout.minZoom(forViewportWidth: width) == expectedMinimum)
        #expect(PageLayout.maxZoom(forViewportWidth: width) == 4 * expectedMinimum)
    }

    #expect(PageLayout.minZoom(forViewportWidth: 0) == 1)
    #expect(PageLayout.maxZoom(forViewportWidth: 0) == 4)
    #expect(PageLayout.minZoom(forViewportWidth: -100) == 1)
    #expect(PageLayout.maxZoom(forViewportWidth: -100) == 4)
}

@Test("Ended zoom scales snap to fit within the fit-relative band")
func endedZoomScalesSnapToFitWithinBand() {
    for width: CGFloat in [768, 1_024] {
        let fit = PageLayout.minZoom(forViewportWidth: width)

        #expect(PageLayout.snapTargetZoom(forEndedZoomScale: fit, viewportWidth: width) == fit)
        #expect(
            PageLayout.snapTargetZoom(forEndedZoomScale: 0.95 * fit, viewportWidth: width) == fit
        )
        #expect(
            PageLayout.snapTargetZoom(forEndedZoomScale: 1.05 * fit, viewportWidth: width) == fit
        )
        #expect(
            PageLayout.snapTargetZoom(forEndedZoomScale: 1.09 * fit, viewportWidth: width) == fit
        )
        #expect(
            PageLayout.snapTargetZoom(forEndedZoomScale: 1.11 * fit, viewportWidth: width) == nil
        )
        #expect(
            PageLayout.snapTargetZoom(forEndedZoomScale: 0.89 * fit, viewportWidth: width) == nil
        )
        #expect(
            PageLayout.snapTargetZoom(forEndedZoomScale: 0.5 * fit, viewportWidth: width) == nil
        )
        #expect(
            PageLayout.snapTargetZoom(forEndedZoomScale: 0.25 * fit, viewportWidth: width) == nil
        )
    }

    // Exact band boundaries, checked where fit == 1 so the ratios are float-exact.
    #expect(
        PageLayout.snapTargetZoom(forEndedZoomScale: PageLayout.snapToFitLowerRatio, viewportWidth: 768) == 1
    )
    #expect(
        PageLayout.snapTargetZoom(forEndedZoomScale: PageLayout.snapToFitUpperRatio, viewportWidth: 768) == 1
    )

    #expect(PageLayout.snapTargetZoom(forEndedZoomScale: 1, viewportWidth: 0) == nil)
    #expect(PageLayout.snapTargetZoom(forEndedZoomScale: -1, viewportWidth: 768) == nil)
}

@Test("Ended zoom scales settle inside logical bounds")
func endedZoomScalesSettleInsideLogicalBounds() {
    let overviewFloor = PageLayout.overviewMinZoom(forViewportWidth: 768)
    let maximum = PageLayout.maxZoom(forViewportWidth: 768)

    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 0.2, viewportWidth: 768) == overviewFloor)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 0.125, viewportWidth: 768) == overviewFloor)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 4.5, viewportWidth: 768) == maximum)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 5, viewportWidth: 768) == maximum)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 0.25, viewportWidth: 768) == nil)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 0.5, viewportWidth: 768) == nil)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 0.95, viewportWidth: 768) == 1)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 2, viewportWidth: 768) == nil)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 4, viewportWidth: 768) == nil)

    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 1, viewportWidth: 0) == nil)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 1, viewportWidth: -768) == nil)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: 0, viewportWidth: 768) == nil)
    #expect(PageLayout.settleTargetZoom(forEndedZoomScale: -1, viewportWidth: 768) == nil)

    let secondWidth: CGFloat = 1_024
    let secondFit = PageLayout.minZoom(forViewportWidth: secondWidth)
    #expect(
        PageLayout.settleTargetZoom(
            forEndedZoomScale: 0.2 * secondFit,
            viewportWidth: secondWidth
        ) == PageLayout.overviewMinZoom(forViewportWidth: secondWidth)
    )
    #expect(
        PageLayout.settleTargetZoom(
            forEndedZoomScale: 4.5 * secondFit,
            viewportWidth: secondWidth
        ) == PageLayout.maxZoom(forViewportWidth: secondWidth)
    )
}

@Test("Anchored zoom offset keeps the visible center in range")
func anchoredZoomOffsetKeepsVisibleCenterInRange() {
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

@Test("Overview minimum zoom is a fraction of fit-to-width")
func overviewMinimumZoomIsFractionOfFitToWidth() {
    for width: CGFloat in [744, 834, 1_194] {
        #expect(
            PageLayout.overviewMinZoom(forViewportWidth: width)
                == PageLayout.overviewZoomFactor
                    * PageLayout.minZoom(forViewportWidth: width)
        )
    }

    #expect(PageLayout.overviewMinZoom(forViewportWidth: 0) == PageLayout.overviewZoomFactor * 1)
    #expect(
        PageLayout.overviewMinZoom(forViewportWidth: -100) == PageLayout.overviewZoomFactor * 1
    )
}
