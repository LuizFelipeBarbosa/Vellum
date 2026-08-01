import CoreGraphics
import Foundation
import PDFKit
import PencilKit
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class NoteExporterTests: XCTestCase {
    func testPDFExportsThreeA4Pages() throws {
        let output = try NoteExporter.export(
            content: makeThreePageContent(),
            title: "Export",
            format: .pdf
        )
        defer { removeOutput(output) }

        assertOutputDirectory(output)
        XCTAssertEqual(output.urls.count, 1)
        let document = try XCTUnwrap(CGPDFDocument(output.urls[0] as CFURL))
        XCTAssertEqual(document.numberOfPages, 3)

        for pageNumber in 1...document.numberOfPages {
            let page = try XCTUnwrap(document.page(at: pageNumber))
            let mediaBox = page.getBoxRect(.mediaBox)
            XCTAssertEqual(mediaBox.width, 595.2, accuracy: 0.5)
            XCTAssertEqual(mediaBox.height, 841.8, accuracy: 0.5)
        }
    }

    func testPNGExportsThreeRasterPages() throws {
        try assertThreePageRasterExport(format: .png)
    }

    func testJPEGExportsThreeRasterPages() throws {
        try assertThreePageRasterExport(format: .jpeg)
    }

    func testEmptyContentExportsOnePageForEveryFormat() throws {
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [],
            imagesByAssetPath: [:],
            pageCount: 4
        )

        for format in NoteExporter.Format.allCases {
            let output = try NoteExporter.export(
                content: content,
                title: "Empty",
                format: format
            )
            defer { removeOutput(output) }

            assertOutputDirectory(output)
            XCTAssertEqual(output.urls.count, 1)
            if format == .pdf {
                let document = try XCTUnwrap(CGPDFDocument(output.urls[0] as CFURL))
                XCTAssertEqual(document.numberOfPages, 1)
            } else {
                XCTAssertNotNil(UIImage(contentsOfFile: output.urls[0].path))
            }
        }
    }

    func testPDFBackedPageWithoutInkExportsAsOnePDFPage() throws {
        let pdfDocument = try PixelComparison.makeSolidPDFDocument(
            color: .blue,
            size: CGSize(width: 320, height: 320)
        )
        let pdfPage = try XCTUnwrap(pdfDocument.page(at: 0))
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [],
            imagesByAssetPath: [:],
            pageCount: 1,
            pdfPagesByBand: [0: pdfPage],
            pdfExpectedBands: [0]
        )
        let output = try NoteExporter.export(
            content: content,
            title: "PDF-backed",
            format: .pdf,
            minimumFilledPages: 1
        )
        defer { removeOutput(output) }

        let document = try XCTUnwrap(CGPDFDocument(output.urls[0] as CFURL))
        XCTAssertEqual(document.numberOfPages, 1)
    }

    func testMissingExpectedPDFPageThrowsBeforeCreatingOutputDirectory() throws {
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [],
            imagesByAssetPath: [:],
            pageCount: 1,
            pdfExpectedBands: [0]
        )
        let directoriesBefore = try temporaryExportDirectoryNames()

        do {
            let output = try NoteExporter.export(
                content: content,
                title: "Missing PDF",
                format: .pdf,
                minimumFilledPages: 1
            )
            defer { removeOutput(output) }
            XCTFail("Expected missingPDFPages")
        } catch NoteExportError.missingPDFPages(let missingBands) {
            XCTAssertEqual(missingBands, [0])
            XCTAssertEqual(
                NoteExportError.missingPDFPages(missingBands).localizedDescription,
                "Export failed: 1 PDF page could not be loaded (missing page: 1)."
            )
        } catch {
            XCTFail("Expected missingPDFPages, got \(error)")
        }

        let directoriesAfter = try temporaryExportDirectoryNames()
        XCTAssertEqual(directoriesAfter, directoriesBefore)
    }

    func testMissingInRangeImageAssetThrowsBeforeCreatingOutputDirectory() throws {
        let assetPath = "assets/missing.png"
        let element = CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: assetPath,
                    originalPixelSize: CanvasSize(width: 100, height: 100)
                )
            ),
            frame: CanvasRect(x: 100, y: 100, width: 100, height: 100)
        )
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [element],
            imagesByAssetPath: [:],
            pageCount: 1
        )
        let directoriesBefore = try temporaryExportDirectoryNames()

        do {
            let output = try NoteExporter.export(
                content: content,
                title: "Missing image",
                format: .pdf
            )
            defer { removeOutput(output) }
            XCTFail("Expected missingImageAssets")
        } catch NoteExportError.missingImageAssets(let missingPaths) {
            XCTAssertEqual(missingPaths, [assetPath])
        } catch {
            XCTFail("Expected missingImageAssets, got \(error)")
        }

        let directoriesAfter = try temporaryExportDirectoryNames()
        XCTAssertEqual(directoriesAfter, directoriesBefore)
    }

    func testOffPageMissingImageAssetDoesNotThrow() throws {
        let missingAssetPath = "assets/off-page-missing.png"
        let presentAssetPath = "assets/in-range.png"
        let offPageElement = CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: missingAssetPath,
                    originalPixelSize: CanvasSize(width: 100, height: 100)
                )
            ),
            frame: CanvasRect(x: 100, y: -300, width: 100, height: 100)
        )
        let inRangeElement = CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: presentAssetPath,
                    originalPixelSize: CanvasSize(width: 100, height: 100)
                )
            ),
            frame: CanvasRect(x: 100, y: 100, width: 100, height: 100)
        )
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [offPageElement, inRangeElement],
            imagesByAssetPath: [
                presentAssetPath: PixelComparison.solidImage(
                    color: .red,
                    size: CGSize(width: 100, height: 100)
                ),
            ],
            pageCount: 1
        )

        let output = try NoteExporter.export(
            content: content,
            title: "Off-page missing image",
            format: .pdf
        )
        defer { removeOutput(output) }

        assertOutputDirectory(output)
        XCTAssertEqual(output.urls.count, 1)
    }

    func testMissingImageAssetPathsPreserveElementOrderWithoutDuplicates() {
        let firstPath = "assets/first-missing.png"
        let secondPath = "assets/second-missing.png"
        let paths = [firstPath, secondPath, firstPath]
        let elements = paths.enumerated().map { index, assetPath in
            CanvasElement(
                content: .image(
                    ImageContent(
                        assetPath: assetPath,
                        originalPixelSize: CanvasSize(width: 100, height: 100)
                    )
                ),
                frame: CanvasRect(
                    x: 100,
                    y: Double(100 + index * 120),
                    width: 100,
                    height: 100
                )
            )
        }
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: elements,
            imagesByAssetPath: [:],
            pageCount: 1
        )

        do {
            let output = try NoteExporter.export(
                content: content,
                title: "Missing images",
                format: .pdf
            )
            defer { removeOutput(output) }
            XCTFail("Expected missingImageAssets")
        } catch NoteExportError.missingImageAssets(let missingPaths) {
            XCTAssertEqual(missingPaths, [firstPath, secondPath])
            let error = NoteExportError.missingImageAssets(missingPaths)
            XCTAssertEqual(
                error.localizedDescription,
                "Export failed: 2 images could not be loaded (missing: \(firstPath), \(secondPath))."
            )
        } catch {
            XCTFail("Expected missingImageAssets, got \(error)")
        }
    }

    func testRotatedImageCrossingPageBoundaryExportsSecondPage() throws {
        let assetPath = "assets/rotated-red.png"
        let centerY = PageGeometry.a4.pageHeight - 30
        let element = CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: assetPath,
                    originalPixelSize: CanvasSize(width: 300, height: 40)
                )
            ),
            frame: CanvasRect(
                x: 234,
                y: Double(centerY - 20),
                width: 300,
                height: 40
            ),
            rotation: .pi / 2
        )
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [element],
            imagesByAssetPath: [
                assetPath: PixelComparison.solidImage(color: .red, size: CGSize(width: 300, height: 40)),
            ],
            pageCount: 1
        )
        let output = try NoteExporter.export(
            content: content,
            title: "Rotated boundary",
            format: .png
        )
        defer { removeOutput(output) }

        XCTAssertEqual(output.urls.count, 2)
        XCTAssertEqual(
            output.urls.map(\.lastPathComponent),
            [
                "Rotated boundary – Page 1.png",
                "Rotated boundary – Page 2.png",
            ]
        )
    }

    func testWrappedTextCrossingPageBoundaryExportsAndDrawsOnSecondPage() throws {
        let frame = CanvasRect(
            x: 304,
            y: Double(PageGeometry.a4.pageHeight - 64),
            width: 160,
            height: 44
        )
        let element = CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Vellum notes wrap across many narrow lines so every captured thought remains visible in a careful export.",
                    fontSize: 32,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame
        )
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [element],
            imagesByAssetPath: [:],
            pageCount: 1
        )
        let output = try NoteExporter.export(
            content: content,
            title: "Wrapped boundary",
            format: .png
        )
        defer { removeOutput(output) }

        assertOutputDirectory(output)
        // The persisted 44pt frame ends 20pt above the page boundary; only the text grown
        // past it reaches page two.
        XCTAssertGreaterThan(element.effectiveBoundingBox.maxY, PageGeometry.a4.pageHeight)
        XCTAssertEqual(output.urls.count, 2)

        let rendered = try PixelComparison.pixelBuffer(
            for: XCTUnwrap(UIImage(contentsOfFile: output.urls[1].path))
        )
        let referenceContent = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [],
            imagesByAssetPath: [:],
            pageCount: 2
        )
        let reference = try PixelComparison.pixelBuffer(
            for: NotePageRenderer.image(
                pageIndex: 1,
                content: referenceContent,
                pointSize: CGSize(
                    width: PageLayout.portraitContentWidth,
                    height: PageGeometry.a4.pageHeight
                ),
                scale: 2
            )
        )
        let pageLocalOverlap = element.effectiveBoundingBox
            .intersection(PageGeometry.a4.pageRect(index: 1))
            .offsetBy(dx: 0, dy: -PageGeometry.a4.pageHeight)

        XCTAssertGreaterThan(
            PixelComparison.differingPixelCount(rendered, reference, in: pageLocalOverlap),
            0
        )
    }

    func testSanitizesTitleInEveryFormatFilename() throws {
        let content = NotePageRenderer.Content(
            drawing: PKDrawing(),
            elements: [],
            imagesByAssetPath: [:],
            pageCount: 1
        )

        for format in NoteExporter.Format.allCases {
            let output = try NoteExporter.export(
                content: content,
                title: "A/B: C",
                format: format
            )
            defer { removeOutput(output) }

            assertOutputDirectory(output)
            let expectedFilename = switch format {
            case .pdf: "A-B- C.pdf"
            case .png: "A-B- C – Page 1.png"
            case .jpeg: "A-B- C – Page 1.jpeg"
            }
            XCTAssertEqual(output.urls.map(\.lastPathComponent), [expectedFilename])
        }
    }

    private func assertThreePageRasterExport(
        format: NoteExporter.Format
    ) throws {
        let output = try NoteExporter.export(
            content: makeThreePageContent(),
            title: "Export",
            format: format
        )
        defer { removeOutput(output) }

        assertOutputDirectory(output)
        XCTAssertEqual(output.urls.count, 3)
        for url in output.urls {
            let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
            let cgImage = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(
                CGFloat(cgImage.width),
                PageGeometry.a4.rasterPageSizePixels.width,
                accuracy: 1
            )
            XCTAssertEqual(
                CGFloat(cgImage.height),
                PageGeometry.a4.rasterPageSizePixels.height,
                accuracy: 1
            )
        }
    }

    private func makeThreePageContent() -> NotePageRenderer.Content {
        let stroke = CanvasFixtures.makeStroke(
            locations: [
                CGPoint(x: 180, y: 80),
                CGPoint(x: 260, y: PageGeometry.a4.pageHeight * 1.4),
                CGPoint(x: 340, y: PageGeometry.a4.pageHeight * 2.5),
            ],
            size: CGSize(width: 12, height: 12)
        )
        let textElement = CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Vellum export",
                    fontSize: 32,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: CanvasRect(x: 80, y: 120, width: 320, height: 80)
        )
        let assetPath = "assets/export.png"
        let imageElement = CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: assetPath,
                    originalPixelSize: CanvasSize(width: 8, height: 4)
                )
            ),
            frame: CanvasRect(
                x: 160,
                y: Double(PageGeometry.a4.pageHeight + 120),
                width: 240,
                height: 120
            )
        )

        return NotePageRenderer.Content(
            drawing: PKDrawing(strokes: [stroke]),
            elements: [textElement, imageElement],
            imagesByAssetPath: [
                assetPath: PixelComparison.solidImage(color: .red, size: CGSize(width: 8, height: 4)),
            ],
            pageCount: 4
        )
    }


    private func assertOutputDirectory(
        _ output: NoteExporter.Output,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            output.directory.lastPathComponent.hasPrefix("VellumExport-"),
            file: file,
            line: line
        )
        for url in output.urls {
            XCTAssertEqual(
                url.deletingLastPathComponent().standardizedFileURL,
                output.directory.standardizedFileURL,
                file: file,
                line: line
            )
        }
    }

    private func removeOutput(_ output: NoteExporter.Output) {
        try? FileManager.default.removeItem(at: output.directory)
    }

    private func temporaryExportDirectoryNames() throws -> Set<String> {
        Set(
            try FileManager.default.contentsOfDirectory(
                at: FileManager.default.temporaryDirectory,
                includingPropertiesForKeys: nil
            )
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("VellumExport-") }
        )
    }
}
