import Foundation
import PDFKit
import VellumCore

enum PDFImportError: Error {
    case unreadable
    case encrypted
    case empty
    case tooManyPages
}

struct PDFImportService {
    static let maxPageCount = 500

    /// Parses and validates PDF `data`; returns the built Note (not yet
    /// persisted) and the relative asset path the caller must save `data` to.
    static func buildNote(
        fromPDFData data: Data,
        title: String
    ) throws -> (note: Note, assetRelativePath: String) {
        guard let document = PDFDocument(data: data) else {
            throw PDFImportError.unreadable
        }
        guard !document.isEncrypted, !document.isLocked else {
            throw PDFImportError.encrypted
        }
        guard document.pageCount > 0 else {
            throw PDFImportError.empty
        }
        guard document.pageCount <= maxPageCount else {
            throw PDFImportError.tooManyPages
        }
        guard let firstPage = document.page(at: 0) else {
            throw PDFImportError.unreadable
        }

        // The note follows the first page's displayed orientation and aspect; mixed-size pages still aspect-fit.
        let mediaBoxSize = firstPage.bounds(for: .mediaBox).size
        let normalizedRotation = ((firstPage.rotation % 360) + 360) % 360
        let displayedPageSize =
            normalizedRotation == 90 || normalizedRotation == 270
            ? CGSize(width: mediaBoxSize.height, height: mediaBoxSize.width)
            : mediaBoxSize
        guard displayedPageSize.width > 0, displayedPageSize.height > 0 else {
            throw PDFImportError.unreadable
        }
        let isLandscape = displayedPageSize.width > displayedPageSize.height

        let assetRelativePath = "assets/pdf-\(UUID().uuidString).pdf"
        let pages = (0..<document.pageCount).map { index in
            let pageID = UUID()
            return NotePage(
                id: pageID,
                order: index,
                plainText: "",
                drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
                background: .pdf,
                pdfPage: PDFPageReference(
                    assetPath: assetRelativePath,
                    pageIndex: index
                ),
                elements: []
            )
        }
        let now = Date()
        let note = Note(
            id: UUID(),
            schemaVersion: Note.currentSchemaVersion,
            revision: 1,
            title: title.isEmpty ? "Untitled" : title,
            tags: [],
            createdAt: now,
            updatedAt: now,
            pages: pages,
            noteType: .pdf,
            backgroundStyle: .blank,
            pageAspectRatio: isLandscape
                ? Double(displayedPageSize.width / displayedPageSize.height)
                : Double(displayedPageSize.height / displayedPageSize.width),
            pageOrientation: isLandscape ? .landscape : .portrait
        )

        return (note, assetRelativePath)
    }
}
