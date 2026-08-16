import CoreGraphics
import PDFKit
import UIKit
@testable import Vellum
import XCTest

final class PdfDocumentStoreTests: XCTestCase {
    func testLoadDocumentReturnsRotationAppliedDisplayedSize() async throws {
        let pageBounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let pdfPage = PDFPage()
        pdfPage.setBounds(pageBounds, for: .mediaBox)
        pdfPage.rotation = 90
        let document = PDFDocument()
        document.insert(pdfPage, at: 0)
        let data = try XCTUnwrap(document.dataRepresentation())

        let store = PdfDocumentStore()
        let loaded = await store.loadDocument(data: data, forAssetPath: "assets/rotated.pdf")
        let metadata = try XCTUnwrap(loaded)

        XCTAssertEqual(metadata.count, 1)
        // Width/height swap because the page's rotation is 90 degrees.
        XCTAssertEqual(metadata[0].displayedMediaBoxSize, CGSize(width: 100, height: 200))
        XCTAssertEqual(metadata[0].pageCount, 1)
    }

    func testVectorPageDataRoundTripsThroughCGPDFDocumentWithOnePage() async throws {
        let document = try PixelComparison.makeSolidPDFDocument(
            color: .red,
            size: CGSize(width: 64, height: 64)
        )
        let data = try XCTUnwrap(document.dataRepresentation())
        let store = PdfDocumentStore()
        let loaded = await store.loadDocument(data: data, forAssetPath: "assets/solid.pdf")
        XCTAssertNotNil(loaded)

        let fetchedVectorData = await store.vectorPageData(assetPath: "assets/solid.pdf", pageIndex: 0)
        let vectorData = try XCTUnwrap(fetchedVectorData)
        let provider = try XCTUnwrap(CGDataProvider(data: vectorData as CFData))
        let cgDocument = try XCTUnwrap(CGPDFDocument(provider))

        XCTAssertEqual(cgDocument.numberOfPages, 1)
    }

    func testRasterReturnsNonNilImageAtRequestedSize() async throws {
        let document = try PixelComparison.makeSolidPDFDocument(
            color: .blue,
            size: CGSize(width: 64, height: 64)
        )
        let data = try XCTUnwrap(document.dataRepresentation())
        let store = PdfDocumentStore()
        let loaded = await store.loadDocument(data: data, forAssetPath: "assets/blue.pdf")
        XCTAssertNotNil(loaded)

        let image = await store.raster(
            assetPath: "assets/blue.pdf",
            pageIndex: 0,
            targetPixelSize: CGSize(width: 128, height: 128),
            invertsColors: false
        )

        let unwrapped = try XCTUnwrap(image)
        XCTAssertGreaterThan(unwrapped.size.width, 0)
        XCTAssertGreaterThan(unwrapped.size.height, 0)
    }

    func testLoadDocumentReturnsNilForUndecodableData() async {
        let store = PdfDocumentStore()
        let metadata = await store.loadDocument(
            data: Data([0x00, 0xFF, 0x13, 0x37]),
            forAssetPath: "assets/bad.pdf"
        )
        XCTAssertNil(metadata)
    }
}
