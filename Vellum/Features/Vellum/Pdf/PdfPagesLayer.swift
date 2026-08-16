import SwiftUI
import UIKit
import VellumCore

struct PdfPagesLayer: View {
    @Environment(\.colorScheme) private var colorScheme

    let cache: PdfPageImageCache
    let pdfBands: Set<Int>
    let viewport: CanvasViewport
    let pageCount: Int
    let geometry: PageGeometry
    private let sortedBands: [Int]

    init(
        cache: PdfPageImageCache,
        pdfBands: Set<Int>,
        viewport: CanvasViewport,
        pageCount: Int,
        geometry: PageGeometry
    ) {
        self.cache = cache
        self.pdfBands = pdfBands
        self.viewport = viewport
        self.pageCount = pageCount
        self.geometry = geometry
        sortedBands = pdfBands.sorted()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(sortedBands, id: \.self) { band in
                if (0..<pageCount).contains(band),
                   let pageID = cache.pageID(forBand: band),
                   let size = cache.displayedPageSize(forBand: band),
                   let image = cachedImage(for: pageID) {
                    let rect = geometry.fittedRect(
                        forSourcePageSize: size,
                        pageIndex: band
                    )
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .compositingGroup()
        .blendMode(colorScheme == .dark ? .screen : .multiply)
        .allowsHitTesting(false)
    }

    private func cachedImage(for pageID: UUID) -> UIImage? {
        let preferredBucket: PdfPageImageCache.ScaleBucket =
            viewport.zoomScale > 1.5 ? .zoomed : .fit
        let fallbackBucket: PdfPageImageCache.ScaleBucket =
            preferredBucket == .zoomed ? .fit : .zoomed
        return cache.images[
            PdfPageImageCache.ImageKey(
                pageID: pageID,
                bucket: preferredBucket,
                isDark: colorScheme == .dark
            )
        ] ?? cache.images[
            PdfPageImageCache.ImageKey(
                pageID: pageID,
                bucket: fallbackBucket,
                isDark: colorScheme == .dark
            )
        ]
    }
}
