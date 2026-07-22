import CoreGraphics

/// Pure geometry constants and calculations for Vellum's paginated canvas.
public enum PageLayout {
    /// Fixed logical canvas width in content points (device-independent).
    public static let contentWidth: CGFloat = 768

    /// A4 aspect: 841.8 / 595.2 (PDF points for 210×297mm at 72dpi).
    public static let a4AspectRatio: CGFloat = 841.8 / 595.2

    /// The logical height of each A4 page in content points.
    public static let pageHeight: CGFloat = contentWidth * a4AspectRatio

    /// A4 in PDF points.
    public static let pdfPageSize = CGSize(width: 595.2, height: 841.8)

    /// Raster export size per page in pixels (768×2 wide, A4 aspect).
    public static let rasterPageSizePixels = CGSize(width: 1536, height: 2172)

    /// Returns the content-space rectangle of the zero-based page at `index`.
    public static func pageRect(index: Int) -> CGRect {
        CGRect(
            x: 0,
            y: CGFloat(index) * pageHeight,
            width: contentWidth,
            height: pageHeight
        )
    }

    /// Returns the total scrollable height for `pageCount` pages.
    public static func contentHeight(pageCount: Int) -> CGFloat {
        CGFloat(pageCount) * pageHeight
    }

    /// Returns the number of pages to display: the filled pages plus one always-blank page ahead.
    public static func pageCount(forContentBottom bottom: CGFloat) -> Int {
        guard bottom > 0 else { return 2 }

        let filled = max(1, Int((bottom / pageHeight).rounded(.up)))
        return filled + 1
    }

    /// Returns the number of non-blank pages to export for content extending to `bottom`.
    public static func exportPageCount(forContentBottom bottom: CGFloat) -> Int {
        guard bottom > 0 else { return 1 }

        return max(1, Int((bottom / pageHeight).rounded(.up)))
    }

    /// Returns the page containing content-space `y`, clamped to the available pages.
    public static func pageIndex(forContentY y: CGFloat, pageCount: Int) -> Int {
        let clampedPageCount = max(1, pageCount)
        guard y > 0 else { return 0 }

        let index = Int((y / pageHeight).rounded(.down))
        return min(index, clampedPageCount - 1)
    }

    /// Returns the fit-to-width zoom for a viewport of `width`.
    public static func minZoom(forViewportWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return width / contentWidth
    }

    /// Lower bound of the fit-relative band within which an ended pinch snaps to fit.
    public static let snapToFitLowerRatio: CGFloat = 0.9

    /// Upper bound of the fit-relative band within which an ended pinch snaps to fit.
    public static let snapToFitUpperRatio: CGFloat = 1.1

    /// Returns the zoom scale an ended pinch should animate to, or nil to settle where it is.
    public static func snapTargetZoom(
        forEndedZoomScale scale: CGFloat,
        viewportWidth width: CGFloat
    ) -> CGFloat? {
        guard width > 0 else { return nil }

        let fit = minZoom(forViewportWidth: width)
        guard fit > 0 else { return nil }
        guard scale > 0 else { return nil }

        let ratio = scale / fit
        guard ratio >= snapToFitLowerRatio else { return nil }
        guard ratio <= snapToFitUpperRatio else { return nil }

        return fit
    }

    /// Returns the vertical content offset that keeps `visibleCenterContentY` centered
    /// after zooming to `scale`, clamped to the scrollable range (top-aligned when the
    /// scaled content is shorter than the viewport).
    public static func anchoredOffsetY(
        visibleCenterContentY: CGFloat,
        scale: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        let maxOffsetY = max(0, contentHeight * scale - viewportHeight)
        let ideal = visibleCenterContentY * scale - viewportHeight / 2
        return min(max(0, ideal), maxOffsetY)
    }

    /// Fraction of fit-to-width the user can zoom out to for the multi-page overview.
    public static let overviewZoomFactor: CGFloat = 0.25

    /// Returns the minimum zoom scale for the multi-page overview (below fit-to-width),
    /// for a viewport of `width`.
    public static func overviewMinZoom(forViewportWidth width: CGFloat) -> CGFloat {
        overviewZoomFactor * minZoom(forViewportWidth: width)
    }

    /// Returns four times the fit-to-width zoom for a viewport of `width`.
    public static func maxZoom(forViewportWidth width: CGFloat) -> CGFloat {
        4 * minZoom(forViewportWidth: width)
    }

    /// How far past the logical zoom limits an elastic pinch may travel.
    public static let zoomOvershootFactor: CGFloat = 0.5

    /// Lowest elastic zoom: overshoot below the overview floor.
    public static func elasticMinZoom(forViewportWidth width: CGFloat) -> CGFloat {
        (1 - zoomOvershootFactor) * overviewMinZoom(forViewportWidth: width)
    }

    /// Highest elastic zoom: overshoot above the maximum.
    public static func elasticMaxZoom(forViewportWidth width: CGFloat) -> CGFloat {
        (1 + zoomOvershootFactor / 2) * maxZoom(forViewportWidth: width)
    }

    /// Returns where an ended pinch should settle: back inside the logical limits,
    /// onto fit when within the snap band, or nil to stay where it is.
    public static func settleTargetZoom(
        forEndedZoomScale scale: CGFloat,
        viewportWidth width: CGFloat
    ) -> CGFloat? {
        guard width > 0, scale > 0 else { return nil }
        let floor = overviewMinZoom(forViewportWidth: width)
        let ceiling = maxZoom(forViewportWidth: width)
        if scale < floor { return floor }
        if scale > ceiling { return ceiling }
        return snapTargetZoom(forEndedZoomScale: scale, viewportWidth: width)
    }
}
