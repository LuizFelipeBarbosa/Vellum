import Foundation
import PDFKit
import UIKit

/// The single owner of every `PDFDocument` for one `PdfPageImageCache` (one per
/// `NoteScreenModel`; split panes get independent stores). No `PDFDocument` or `PDFPage`
/// reference is ever handed to a caller — only Sendable value snapshots (`PageMetadata`,
/// `UIImage`, `Data`) cross back out. This is the sole invariant that makes the metadata
/// mirror in `PdfPageImageCache` safe to cache: nothing here ever mutates a document after
/// `loadDocument` parses it. If a page-mutation API is ever added to this actor, every
/// cached `PageMetadata` snapshot must be invalidated and re-fetched at that point.
actor PdfDocumentStore {
    struct PageMetadata: Sendable, Equatable {
        let displayedMediaBoxSize: CGSize
        let pageCount: Int
    }

    private var documents: [String: PDFDocument] = [:]

    /// Parses off-main. Returns per-page metadata for the whole document, or nil if
    /// undecodable.
    func loadDocument(data: Data, forAssetPath assetPath: String) -> [PageMetadata]? {
        guard let document = PDFDocument(data: data) else { return nil }
        documents[assetPath] = document

        let pageCount = document.pageCount
        var metadata: [PageMetadata] = []
        metadata.reserveCapacity(pageCount)
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            metadata.append(
                PageMetadata(
                    displayedMediaBoxSize: Self.displayedMediaBoxSize(for: page),
                    pageCount: pageCount
                )
            )
        }
        return metadata
    }

    func removeAllDocuments() {
        documents.removeAll()
    }

    /// Thumbnail-style raster for the canvas cache and for PNG/JPEG export/thumbnails:
    /// `PDFPage.thumbnail(of:for:.mediaBox)`, then `PdfRasterAppearance` inversion when
    /// `invertsColors` is set — the inversion runs on this actor because `CIContext` is
    /// documented thread-safe (see the comment on `PdfRasterAppearance.context`).
    func raster(
        assetPath: String,
        pageIndex: Int,
        targetPixelSize: CGSize,
        invertsColors: Bool
    ) -> sending UIImage? {
        guard let document = documents[assetPath],
              let page = document.page(at: pageIndex) else {
            return nil
        }
        let image = page.thumbnail(of: targetPixelSize, for: .mediaBox)
        return invertsColors ? PdfRasterAppearance.invertedPreservingHue(image) : image
    }

    /// Vector-fidelity single page for export: builds a new `PDFDocument`, inserts a copy
    /// of the page, and returns `dataRepresentation()`. The caller parses its OWN
    /// `CGPDFDocument` from this `Data` — vector content identical, zero shared PDFKit state.
    func vectorPageData(assetPath: String, pageIndex: Int) -> Data? {
        guard let document = documents[assetPath],
              let page = document.page(at: pageIndex),
              let copiedPage = page.copy() as? PDFPage else {
            return nil
        }
        let singlePageDocument = PDFDocument()
        singlePageDocument.insert(copiedPage, at: 0)
        return singlePageDocument.dataRepresentation()
    }

    private static func displayedMediaBoxSize(for page: PDFPage) -> CGSize {
        let size = page.bounds(for: .mediaBox).size
        let rotation = ((page.rotation % 360) + 360) % 360
        guard rotation == 90 || rotation == 270 else { return size }
        return CGSize(width: size.height, height: size.width)
    }
}
