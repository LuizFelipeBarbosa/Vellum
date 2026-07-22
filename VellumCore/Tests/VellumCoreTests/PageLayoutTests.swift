import CoreGraphics
import Testing
@testable import VellumCore

@Test("Page dimensions use the A4 aspect ratio")
func pageDimensionsUseA4AspectRatio() {
    #expect(PageLayout.contentWidth == 768)
    #expect(PageLayout.a4AspectRatio == CGFloat(841.8 / 595.2))
    #expect(PageLayout.pageHeight == PageLayout.contentWidth * PageLayout.a4AspectRatio)
    #expect(PageLayout.pdfPageSize == CGSize(width: 595.2, height: 841.8))
    #expect(PageLayout.rasterPageSizePixels == CGSize(width: 1_536, height: 2_172))
}

@Test("Page rectangles are stacked in content space")
func pageRectanglesAreStackedInContentSpace() {
    for index in 0...3 {
        let rect = PageLayout.pageRect(index: index)

        #expect(rect.origin.x == 0)
        #expect(rect.origin.y == CGFloat(index) * PageLayout.pageHeight)
        #expect(rect.width == PageLayout.contentWidth)
        #expect(rect.height == PageLayout.pageHeight)
    }
}

@Test("Content height is the page count times page height")
func contentHeightMatchesPageCount() {
    for pageCount in [0, 1, 2, 3, 8] {
        #expect(
            PageLayout.contentHeight(pageCount: pageCount)
                == CGFloat(pageCount) * PageLayout.pageHeight
        )
    }
}

@Test("Display page count keeps one blank page ahead")
func displayPageCountKeepsOneBlankPageAhead() {
    let height = PageLayout.pageHeight
    let epsilon: CGFloat = 0.000_001

    #expect(PageLayout.pageCount(forContentBottom: 0) == 2)
    #expect(PageLayout.pageCount(forContentBottom: -height) == 2)
    #expect(PageLayout.pageCount(forContentBottom: 0.5 * height) == 2)
    #expect(PageLayout.pageCount(forContentBottom: height) == 2)
    #expect(PageLayout.pageCount(forContentBottom: height + epsilon) == 3)
    #expect(PageLayout.pageCount(forContentBottom: 1.5 * height) == 3)
    #expect(PageLayout.pageCount(forContentBottom: 2 * height + epsilon) == 4)
}

@Test("Export page count excludes the trailing growth page")
func exportPageCountExcludesTrailingGrowthPage() {
    let height = PageLayout.pageHeight
    let epsilon: CGFloat = 0.000_001

    #expect(PageLayout.exportPageCount(forContentBottom: 0) == 1)
    #expect(PageLayout.exportPageCount(forContentBottom: height) == 1)
    #expect(PageLayout.exportPageCount(forContentBottom: 2 * height + epsilon) == 3)
}

@Test("Page index is clamped to the available pages")
func pageIndexIsClampedToAvailablePages() {
    let height = PageLayout.pageHeight

    #expect(PageLayout.pageIndex(forContentY: -10, pageCount: 3) == 0)
    #expect(PageLayout.pageIndex(forContentY: 1.5 * height, pageCount: 3) == 1)
    #expect(PageLayout.pageIndex(forContentY: 4 * height, pageCount: 3) == 2)
    #expect(PageLayout.pageIndex(forContentY: height, pageCount: 0) == 0)
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
