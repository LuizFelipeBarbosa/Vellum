import Observation
import UIKit
import VellumCore

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

    private var bandMetadata: [String: [PdfDocumentStore.PageMetadata]] = [:]
    private var inFlight = Set<ImageKey>()
    private var lastRequestSequenceByKey: [ImageKey: Int] = [:]
    private var requestSequence = 0
    private var lastVisibleWindowRequest: VisibleWindowRequest?
    private var pinnedPageIDs: Set<UUID> = []
    private var isDarkAppearance = false
    private let maximumByteCost: Int
    let documentStore = PdfDocumentStore()

    init(maximumByteCost: Int = PdfPageImageCache.byteBudget) {
        self.maximumByteCost = maximumByteCost
    }

    var cachedByteCost: Int {
        images.values.reduce(into: 0) { total, image in
            total += Self.byteCost(of: image)
        }
    }

    @discardableResult
    func loadDocument(data: Data, forAssetPath assetPath: String) async -> Bool {
        guard let metadata = await documentStore.loadDocument(
            data: data,
            forAssetPath: assetPath
        ) else {
            return false
        }
        bandMetadata[assetPath] = metadata
        if let request = lastVisibleWindowRequest {
            updateVisibleWindow(
                bands: request.bands,
                bucket: request.bucket,
                displayScale: request.displayScale
            )
        }
        return true
    }

    func clearCaches() {
        bandMetadata.removeAll()
        let store = documentStore
        Task { await store.removeAllDocuments() }
        images.removeAll()
        inFlight.removeAll()
        lastRequestSequenceByKey.removeAll()
        requestSequence = 0
        lastVisibleWindowRequest = nil
        pinnedPageIDs.removeAll()
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

    func displayedPageSize(forBand band: Int) -> CGSize? {
        guard let reference = pageReference(forBand: band),
              let metadata = bandMetadata[reference.assetPath],
              metadata.indices.contains(reference.pageIndex) else {
            return nil
        }
        return metadata[reference.pageIndex].displayedMediaBoxSize
    }

    func bandRef(forBand band: Int) -> PdfBandRef? {
        guard let reference = pageReference(forBand: band),
              let metadata = bandMetadata[reference.assetPath],
              metadata.indices.contains(reference.pageIndex) else {
            return nil
        }
        return PdfBandRef(
            assetPath: reference.assetPath,
            pageIndex: reference.pageIndex,
            displayedSize: metadata[reference.pageIndex].displayedMediaBoxSize
        )
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
                  let metadata = bandMetadata[reference.assetPath],
                  metadata.indices.contains(reference.pageIndex) else {
                continue
            }

            inFlight.insert(key)
            let targetPixelSize = Self.targetPixelSize(
                for: metadata[reference.pageIndex].displayedMediaBoxSize,
                bucket: bucket,
                displayScale: displayScale,
                contentWidth: contentWidth
            )
            let assetPath = reference.assetPath
            let pageIndex = reference.pageIndex
            let invertsColors = isDarkAppearance
            let store = documentStore

            Task { [weak self] in
                guard let self else { return }
                let image = await store.raster(
                    assetPath: assetPath,
                    pageIndex: pageIndex,
                    targetPixelSize: targetPixelSize,
                    invertsColors: invertsColors
                )
                inFlight.remove(key)
                if let image {
                    insertImage(image, for: key)
                }
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
        for sourceSize: CGSize,
        bucket: ScaleBucket,
        displayScale: CGFloat,
        contentWidth: CGFloat
    ) -> CGSize {
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
}
