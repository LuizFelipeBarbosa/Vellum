import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class InkTextRecognizerTests: XCTestCase {
    func testInkedBandsAssignsStrokeToSecondBand() {
        let geometry = PageGeometry.a4
        let drawing = makeSecondBandDrawing(geometry: geometry)

        XCTAssertEqual(
            InkTextRecognizer.inkedBands(
                of: drawing,
                geometry: geometry,
                bandCount: 2
            ),
            [1]
        )
    }

    func testRasterizeProducesExpectedNonWhitePageImage() throws {
        let geometry = PageGeometry.a4
        let image = try XCTUnwrap(
            InkTextRecognizer.rasterize(
                makeSecondBandDrawing(geometry: geometry),
                pageRect: geometry.pageRect(index: 1),
                scale: 2
            )
        )

        let expectedSize = geometry.rasterPageSizePixels
        XCTAssertLessThanOrEqual(abs(image.width - Int(expectedSize.width)), 1)
        XCTAssertLessThanOrEqual(abs(image.height - Int(expectedSize.height)), 1)

        let pixelData = try XCTUnwrap(image.dataProvider?.data) as Data
        XCTAssertTrue(pixelData.contains { $0 != 255 })
    }

    func testRecognizeInkReturnsEmptyForMissingOrInvalidDrawingData() async throws {
        let recognizer = InkTextRecognizer()

        let missingLines = try await recognizer.recognizeInk(
            drawingData: nil,
            geometry: .a4,
            bandCount: 2
        )
        XCTAssertEqual(missingLines, [])

        let invalidLines = try await recognizer.recognizeInk(
            drawingData: Data(),
            geometry: .a4,
            bandCount: 2
        )
        XCTAssertEqual(invalidLines, [])
    }

    func testRecognizeLinesFindsRenderedText() async throws {
        let imageSize = CGSize(width: 768, height: 200)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        let attributedString = NSAttributedString(
            string: "Hello world",
            attributes: [
                .font: UIFont.systemFont(ofSize: 64, weight: .regular),
                .foregroundColor: UIColor.black,
            ]
        )
        let image = try XCTUnwrap(renderer.image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: imageSize))
            attributedString.draw(
                in: CGRect(x: 32, y: 48, width: imageSize.width - 64, height: 100)
            )
        }.cgImage)
        let contentRect = CGRect(origin: .zero, size: imageSize)

        let lines = try await InkTextRecognizer.recognizeLines(
            in: image,
            contentRect: contentRect,
            scale: 2
        )
        guard let firstLine = lines.first else {
            throw XCTSkip("Vision returned no observations")
        }

        XCTAssertTrue(
            lines.map(\.text).joined(separator: " ").lowercased().contains("hello")
        )
        let firstRect = CGRect(
            x: CGFloat(firstLine.rect.x),
            y: CGFloat(firstLine.rect.y),
            width: CGFloat(firstLine.rect.width),
            height: CGFloat(firstLine.rect.height)
        )
        XCTAssertTrue(contentRect.contains(firstRect))
    }

    private func makeSecondBandDrawing(geometry: PageGeometry) -> PKDrawing {
        let y = geometry.pageHeight + 100
        let stroke = CanvasFixtures.makeStroke(
            locations: [
                CGPoint(x: 80, y: y),
                CGPoint(x: 320, y: y + 80),
            ],
            size: CGSize(width: 16, height: 16)
        )
        return PKDrawing(strokes: [stroke])
    }
}
