import PDFKit
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(pdfBands.sorted(), id: \.self) { band in
                if (0..<pageCount).contains(band),
                   let pageID = cache.pageID(forBand: band),
                   let page = cache.page(forBand: band),
                   let image = cachedImage(for: pageID) {
                    let rect = geometry.fittedRect(
                        forSourcePageSize: displayedMediaBoxSize(for: page),
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

    private func displayedMediaBoxSize(for page: PDFPage) -> CGSize {
        let size = page.bounds(for: .mediaBox).size
        let rotation = ((page.rotation % 360) + 360) % 360
        guard rotation == 90 || rotation == 270 else { return size }
        return CGSize(width: size.height, height: size.width)
    }
}
