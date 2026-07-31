import Observation
import PDFKit
import UIKit
import VellumCore

private struct PdfPageRenderRequest: @unchecked Sendable {
    let page: PDFPage
    let targetPixelSize: CGSize
    let invertsColors: Bool
}

private struct PdfPageRenderResult: @unchecked Sendable {
    let image: UIImage
}

private actor PdfPageRenderer {
    func render(_ request: PdfPageRenderRequest) -> PdfPageRenderResult {
        let image = request.page.thumbnail(
            of: request.targetPixelSize,
            for: .mediaBox
        )
        return PdfPageRenderResult(
            image: request.invertsColors
                ? PdfRasterAppearance.invertedPreservingHue(image)
                : image
        )
    }
}

@MainActor
@Observable
final class PdfPageImageCache {
    private static let byteBudget = 128 * 1024 * 1024
    private static let fitPixelDimensionCap: CGFloat = 3072
    private static let zoomedPixelDimensionCap: CGFloat = 2048

    enum ScaleBucket: Hashable {
        case fit
        case zoomed
    }

    struct ImageKey: Hashable {
        let pageID: UUID
        let bucket: ScaleBucket
        let isDark: Bool

        init(pageID: UUID, bucket: ScaleBucket, isDark: Bool = false) {
            self.pageID = pageID
            self.bucket = bucket
            self.isDark = isDark
        }
    }

    private struct VisibleWindowRequest {
        let bands: ClosedRange<Int>
        let bucket: ScaleBucket
        let displayScale: CGFloat
    }

    private(set) var images: [ImageKey: UIImage] = [:]
    var pagesProvider: (() -> [NotePage])?
    var contentWidth: CGFloat = PageGeometry.a4.contentWidth

    private var documents: [String: PDFDocument] = [:]
    private var inFlight = Set<ImageKey>()
    private var lastRequestSequenceByKey: [ImageKey: Int] = [:]
    private var requestSequence = 0
    private var lastVisibleWindowRequest: VisibleWindowRequest?
    private var pinnedPageIDs: Set<UUID> = []
    private var isDarkAppearance = false
    private let maximumByteCost: Int
    private let renderer = PdfPageRenderer()

    init(maximumByteCost: Int = PdfPageImageCache.byteBudget) {
        self.maximumByteCost = maximumByteCost
    }

    var cachedByteCost: Int {
        images.values.reduce(into: 0) { total, image in
            total += Self.byteCost(of: image)
        }
    }

    func setDocument(_ doc: PDFDocument, forAssetPath assetPath: String) {
        documents[assetPath] = doc
        if let request = lastVisibleWindowRequest {
            updateVisibleWindow(
                bands: request.bands,
                bucket: request.bucket,
                displayScale: request.displayScale
            )
        }
    }

    func setAppearance(isDark: Bool) {
        guard isDark != isDarkAppearance else { return }
        isDarkAppearance = isDark

        let staleKeys = images.keys.filter { $0.isDark != isDarkAppearance }
        for key in staleKeys {
            images[key] = nil
            lastRequestSequenceByKey[key] = nil
        }
        let staleRequestKeys = lastRequestSequenceByKey.keys.filter {
            $0.isDark != isDarkAppearance
        }
        for key in staleRequestKeys {
            lastRequestSequenceByKey[key] = nil
        }

        if let request = lastVisibleWindowRequest {
            updateVisibleWindow(
                bands: request.bands,
                bucket: request.bucket,
                displayScale: request.displayScale
            )
        }
    }

    func page(forBand band: Int) -> PDFPage? {
        guard let reference = pageReference(forBand: band),
              let document = documents[reference.assetPath] else {
            return nil
        }
        return document.page(at: reference.pageIndex)
    }

    func pageID(forBand band: Int) -> UUID? {
        let pages = pagesProvider?() ?? []
        guard pages.indices.contains(band) else { return nil }
        return pages[band].id
    }

    func updateVisibleWindow(
        bands: ClosedRange<Int>,
        bucket: ScaleBucket,
        displayScale: CGFloat
    ) {
        lastVisibleWindowRequest = VisibleWindowRequest(
            bands: bands,
            bucket: bucket,
            displayScale: displayScale
        )

        let lowerBound = max(0, bands.lowerBound - 1)
        let upperBound = max(lowerBound, bands.upperBound + 1)
        let pages = pagesProvider?() ?? []
        var visiblePageIDs = Set<UUID>()

        for band in lowerBound...upperBound {
            guard pages.indices.contains(band),
                  let reference = pages[band].pdfPage else {
                continue
            }

            let pageID = pages[band].id
            visiblePageIDs.insert(pageID)
            let key = ImageKey(
                pageID: pageID,
                bucket: bucket,
                isDark: isDarkAppearance
            )
            touch(key)
            guard images[key] == nil,
                  !inFlight.contains(key),
                  let page = documents[reference.assetPath]?.page(at: reference.pageIndex) else {
                continue
            }

            inFlight.insert(key)
            let targetPixelSize = Self.targetPixelSize(
                for: page,
                bucket: bucket,
                displayScale: displayScale,
                contentWidth: contentWidth
            )
            let request = PdfPageRenderRequest(
                page: page,
                targetPixelSize: targetPixelSize,
                invertsColors: isDarkAppearance
            )

            Task { [weak self] in
                guard let self else { return }
                let result = await renderer.render(request)
                inFlight.remove(key)
                insertImage(result.image, for: key)
            }
        }

        pinnedPageIDs = visiblePageIDs
        evictIfNeeded()
    }

    private func pageReference(forBand band: Int) -> PDFPageReference? {
        let pages = pagesProvider?() ?? []
        guard pages.indices.contains(band) else { return nil }
        return pages[band].pdfPage
    }

    private func touch(_ key: ImageKey) {
        requestSequence += 1
        lastRequestSequenceByKey[key] = requestSequence
    }

    func insertImage(_ image: UIImage, for key: ImageKey) {
        guard key.isDark == isDarkAppearance else { return }
        images[key] = image
        touch(key)
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        var totalCost = cachedByteCost
        for bucket in [ScaleBucket.zoomed, .fit] {
            while totalCost > maximumByteCost {
                let candidates = images.keys.filter {
                    $0.bucket == bucket && !pinnedPageIDs.contains($0.pageID)
                }
                guard let leastRecentKey = candidates.min(by: { lhs, rhs in
                    lastRequestSequenceByKey[lhs, default: 0]
                        < lastRequestSequenceByKey[rhs, default: 0]
                }) else {
                    break
                }
                if let image = images.removeValue(forKey: leastRecentKey) {
                    totalCost -= Self.byteCost(of: image)
                }
                lastRequestSequenceByKey[leastRecentKey] = nil
            }
        }
    }

    private static func byteCost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale)
            * Int(image.size.height * image.scale)
            * 4
    }

    private static func targetPixelSize(
        for page: PDFPage,
        bucket: ScaleBucket,
        displayScale: CGFloat,
        contentWidth: CGFloat
    ) -> CGSize {
        let sourceSize = displayedMediaBoxSize(for: page)
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }

        let resolvedDisplayScale =
            displayScale.isFinite && displayScale > 0 ? displayScale : 2
        let bucketMultiplier: CGFloat = bucket == .zoomed ? 2 : 1
        let targetWidth = contentWidth
            * resolvedDisplayScale
            * bucketMultiplier
        let targetHeight = targetWidth * sourceSize.height / sourceSize.width
        let dimensionCap = bucket == .zoomed
            ? zoomedPixelDimensionCap
            : fitPixelDimensionCap
        let capScale = min(1, dimensionCap / max(targetWidth, targetHeight))
        return CGSize(
            width: targetWidth * capScale,
            height: targetHeight * capScale
        )
    }

    private static func displayedMediaBoxSize(for page: PDFPage) -> CGSize {
        let size = page.bounds(for: .mediaBox).size
        let rotation = ((page.rotation % 360) + 360) % 360
        guard rotation == 90 || rotation == 270 else { return size }
        return CGSize(width: size.height, height: size.width)
    }
}
