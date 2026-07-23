import PDFKit
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class PdfPageImageCacheTests: XCTestCase {
    func testByteBudgetEvictsLeastRecentlyUsedKeysUntilUnderBudget() {
        let cache = PdfPageImageCache(maximumByteCost: 250)
        let firstKey = makeKey(bucket: .fit)
        let secondKey = makeKey(bucket: .fit)
        let thirdKey = makeKey(bucket: .fit)
        let image = makeImage(width: 5, height: 5)

        cache.insertImage(image, for: firstKey)
        cache.insertImage(image, for: secondKey)
        cache.insertImage(image, for: thirdKey)

        XCTAssertNil(cache.images[firstKey])
        XCTAssertNotNil(cache.images[secondKey])
        XCTAssertNotNil(cache.images[thirdKey])
        XCTAssertEqual(cache.cachedByteCost, 200)
    }

    func testZoomedInsertKeepsFitImageForSamePage() {
        let cache = PdfPageImageCache(maximumByteCost: 1_000)
        let pageID = UUID()
        let fitKey = PdfPageImageCache.ImageKey(pageID: pageID, bucket: .fit)
        let zoomedKey = PdfPageImageCache.ImageKey(pageID: pageID, bucket: .zoomed)
        let image = makeImage(width: 5, height: 5)

        cache.insertImage(image, for: fitKey)
        cache.insertImage(image, for: zoomedKey)

        XCTAssertNotNil(cache.images[fitKey])
        XCTAssertNotNil(cache.images[zoomedKey])
        XCTAssertEqual(cache.cachedByteCost, 200)
    }

    func testVisibleWindowRequestRefreshesCachedKeyRecency() {
        let cache = PdfPageImageCache(maximumByteCost: 300)
        let refreshedPageID = UUID()
        let refreshedKey = PdfPageImageCache.ImageKey(
            pageID: refreshedPageID,
            bucket: .fit
        )
        let untouchedKey = makeKey(bucket: .fit)
        let newestKey = makeKey(bucket: .fit)
        let image = makeImage(width: 5, height: 5)
        let pages = [
            makePDFPage(id: refreshedPageID),
            makePDFPage(id: UUID()),
            makePDFPage(id: UUID()),
            makePDFPage(id: UUID()),
        ]

        cache.insertImage(image, for: refreshedKey)
        cache.insertImage(image, for: untouchedKey)
        cache.pagesProvider = {
            pages
        }

        cache.updateVisibleWindow(
            bands: 0...0,
            bucket: .fit,
            displayScale: 1
        )
        cache.updateVisibleWindow(
            bands: 3...3,
            bucket: .fit,
            displayScale: 1
        )
        cache.insertImage(makeImage(width: 5, height: 10), for: newestKey)

        XCTAssertNotNil(cache.images[refreshedKey])
        XCTAssertNil(cache.images[untouchedKey])
        XCTAssertNotNil(cache.images[newestKey])
        XCTAssertEqual(cache.cachedByteCost, 300)
    }

    func testVisibleWindowPagesArePinnedOverMoreRecentOffWindowPage() {
        let cache = PdfPageImageCache(maximumByteCost: 200)
        let pageIDs = [UUID(), UUID(), UUID(), UUID()]
        let pages = pageIDs.map(makePDFPage)
        let pinnedKeys = pageIDs.prefix(3).flatMap { pageID in
            [
                PdfPageImageCache.ImageKey(pageID: pageID, bucket: .fit),
                PdfPageImageCache.ImageKey(pageID: pageID, bucket: .zoomed),
            ]
        }
        let offWindowKey = PdfPageImageCache.ImageKey(
            pageID: pageIDs[3],
            bucket: .fit
        )
        let image = makeImage(width: 5, height: 5)
        cache.pagesProvider = {
            pages
        }

        cache.updateVisibleWindow(
            bands: 1...1,
            bucket: .fit,
            displayScale: 1
        )
        for key in pinnedKeys {
            cache.insertImage(image, for: key)
        }
        cache.insertImage(image, for: offWindowKey)

        for key in pinnedKeys {
            XCTAssertNotNil(cache.images[key])
        }
        XCTAssertNil(cache.images[offWindowKey])
        XCTAssertEqual(cache.cachedByteCost, 600)
    }

    func testEvictionRemovesZoomedImagesBeforeFitImages() {
        let cache = PdfPageImageCache(maximumByteCost: 300)
        let firstPageID = UUID()
        let secondPageID = UUID()
        let firstFitKey = PdfPageImageCache.ImageKey(
            pageID: firstPageID,
            bucket: .fit
        )
        let firstZoomedKey = PdfPageImageCache.ImageKey(
            pageID: firstPageID,
            bucket: .zoomed
        )
        let secondFitKey = PdfPageImageCache.ImageKey(
            pageID: secondPageID,
            bucket: .fit
        )
        let secondZoomedKey = PdfPageImageCache.ImageKey(
            pageID: secondPageID,
            bucket: .zoomed
        )
        let image = makeImage(width: 5, height: 5)

        cache.insertImage(image, for: firstFitKey)
        cache.insertImage(image, for: firstZoomedKey)
        cache.insertImage(image, for: secondFitKey)
        cache.insertImage(image, for: secondZoomedKey)

        XCTAssertNotNil(cache.images[firstFitKey])
        XCTAssertNil(cache.images[firstZoomedKey])
        XCTAssertNotNil(cache.images[secondFitKey])
        XCTAssertNotNil(cache.images[secondZoomedKey])
        XCTAssertEqual(cache.cachedByteCost, 300)
    }

    func testSetAppearanceFlushesMismatchedAppearanceEntries() {
        let cache = PdfPageImageCache(maximumByteCost: 1_000)
        let firstKey = makeKey(bucket: .fit)
        let secondKey = makeKey(bucket: .zoomed)
        let image = makeImage(width: 5, height: 5)

        cache.insertImage(image, for: firstKey)
        cache.insertImage(image, for: secondKey)

        XCTAssertGreaterThan(cache.cachedByteCost, 0)

        cache.setAppearance(isDark: true)

        XCTAssertNil(cache.images[firstKey])
        XCTAssertNil(cache.images[secondKey])
        XCTAssertEqual(cache.cachedByteCost, 0)
    }

    func testInsertWithMismatchedAppearanceIsIgnored() {
        let cache = PdfPageImageCache(maximumByteCost: 1_000)
        let darkKey = makeKey(bucket: .fit, isDark: true)

        cache.insertImage(makeImage(width: 5, height: 5), for: darkKey)

        XCTAssertNil(cache.images[darkKey])
        XCTAssertEqual(cache.cachedByteCost, 0)
    }

    func testZoomedInsertKeepsFitImageForCurrentAppearance() {
        let cache = PdfPageImageCache(maximumByteCost: 1_000)
        let pageID = UUID()
        let lightFitKey = PdfPageImageCache.ImageKey(
            pageID: pageID,
            bucket: .fit
        )
        let darkFitKey = PdfPageImageCache.ImageKey(
            pageID: pageID,
            bucket: .fit,
            isDark: true
        )
        let darkZoomedKey = PdfPageImageCache.ImageKey(
            pageID: pageID,
            bucket: .zoomed,
            isDark: true
        )
        let image = makeImage(width: 5, height: 5)

        cache.insertImage(image, for: lightFitKey)
        XCTAssertNotNil(cache.images[lightFitKey])

        cache.setAppearance(isDark: true)
        XCTAssertNil(cache.images[lightFitKey])

        cache.insertImage(image, for: darkFitKey)
        cache.insertImage(image, for: darkZoomedKey)

        XCTAssertNotNil(cache.images[darkFitKey])
        XCTAssertNotNil(cache.images[darkZoomedKey])
    }

    private func makeKey(
        bucket: PdfPageImageCache.ScaleBucket,
        isDark: Bool = false
    ) -> PdfPageImageCache.ImageKey {
        PdfPageImageCache.ImageKey(
            pageID: UUID(),
            bucket: bucket,
            isDark: isDark
        )
    }

    private func makePDFPage(id: UUID) -> NotePage {
        NotePage(
            id: id,
            order: 0,
            plainText: "",
            drawingAssetPath: "pages/\(id.uuidString)/drawing.data",
            background: .pdf,
            pdfPage: PDFPageReference(assetPath: "assets/source.pdf", pageIndex: 0)
        )
    }

    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
