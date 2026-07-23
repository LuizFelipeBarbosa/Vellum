import PDFKit
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class PdfImportServiceTests: XCTestCase {
    func testBuildNoteCreatesPDFBackedPageForEveryDocumentPage() throws {
        let result = try PDFImportService.buildNote(
            fromPDFData: makePDF(pageCount: 3),
            title: "Imported PDF"
        )

        XCTAssertEqual(result.note.pages.count, 3)
        XCTAssertEqual(result.note.pages.map(\.order), [0, 1, 2])
        XCTAssertEqual(result.note.noteType, .pdf)
        XCTAssertEqual(result.note.backgroundStyle, .blank)
        XCTAssertTrue(result.assetRelativePath.hasPrefix("assets/pdf-"))
        XCTAssertTrue(result.assetRelativePath.hasSuffix(".pdf"))

        for (index, page) in result.note.pages.enumerated() {
            XCTAssertEqual(page.background, .pdf)
            XCTAssertEqual(page.pdfPage?.pageIndex, index)
            XCTAssertEqual(page.pdfPage?.assetPath, result.assetRelativePath)
        }
    }

    func testEmptyDataIsUnreadable() {
        XCTAssertThrowsError(
            try PDFImportService.buildNote(fromPDFData: Data(), title: "Empty")
        ) { error in
            guard case PDFImportError.unreadable = error else {
                XCTFail("Expected unreadable, got \(error)")
                return
            }
        }
    }

    func testGarbageDataIsUnreadable() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE])

        XCTAssertThrowsError(
            try PDFImportService.buildNote(fromPDFData: garbage, title: "Garbage")
        ) { error in
            guard case PDFImportError.unreadable = error else {
                XCTFail("Expected unreadable, got \(error)")
                return
            }
        }
    }

    func testLetterPDFSetsTheNoteAspectRatio() throws {
        let result = try PDFImportService.buildNote(
            fromPDFData: makePDF(
                pageCount: 1,
                pageSize: CGSize(width: 612, height: 792)
            ),
            title: "Letter"
        )

        XCTAssertEqual(result.note.pageAspectRatio, 792.0 / 612.0, accuracy: 0.001)
    }

    func testRotatedFirstPageSwapsTheDerivedAspectRatio() throws {
        let unrotatedData = makePDF(
            pageCount: 1,
            pageSize: CGSize(width: 612, height: 792)
        )
        let document = try XCTUnwrap(PDFDocument(data: unrotatedData))
        let page = try XCTUnwrap(document.page(at: 0))
        page.rotation = 90
        let rotatedData = try XCTUnwrap(document.dataRepresentation())

        let result = try PDFImportService.buildNote(
            fromPDFData: rotatedData,
            title: "Rotated Letter"
        )

        XCTAssertEqual(result.note.pageAspectRatio, 612.0 / 792.0, accuracy: 0.001)
    }

    // A 501-page fixture is intentionally omitted because it is expensive to generate.

    private func makePDF(
        pageCount: Int,
        pageSize: CGSize = CGSize(width: 200, height: 300)
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize)
        )
        return renderer.pdfData { context in
            for _ in 0..<pageCount {
                context.beginPage()
            }
        }
    }
}
