import Foundation
import PencilKit
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class NotePageRendererTests: XCTestCase {
    func testInkIsCroppedToItsPage() throws {
        let relativeY = PageLayout.pageHeight / 2
        let absoluteY = PageLayout.pageHeight + relativeY
        let stroke = makeStroke(
            locations: [
                CGPoint(x: 300, y: absoluteY - 24),
                CGPoint(x: 300, y: absoluteY),
                CGPoint(x: 300, y: absoluteY + 24),
            ],
            size: CGSize(width: 20, height: 20)
        )
        let content = makeContent(drawing: PKDrawing(strokes: [stroke]), pageCount: 2)
        let emptyContent = makeContent(pageCount: 2)
        let firstPage = render(pageIndex: 0, content: content)
        let firstPageReference = render(pageIndex: 0, content: emptyContent)
        let secondPage = render(pageIndex: 1, content: content)
        let secondPageReference = render(pageIndex: 1, content: emptyContent)
        let sampleRect = CGRect(x: 280, y: relativeY - 44, width: 40, height: 88)

        let firstPixels = try pixelBuffer(for: firstPage)
        let firstReferencePixels = try pixelBuffer(for: firstPageReference)
        let secondPixels = try pixelBuffer(for: secondPage)
        let secondReferencePixels = try pixelBuffer(for: secondPageReference)

        XCTAssertEqual(
            differingPixelCount(firstPixels, firstReferencePixels, in: sampleRect),
            0
        )
        XCTAssertGreaterThan(
            differingPixelCount(secondPixels, secondReferencePixels, in: sampleRect),
            0
        )
    }

    func testTextElementDrawsInsideItsFrame() throws {
        let frame = CanvasRect(
            x: 140,
            y: Double(PageLayout.pageHeight / 2 - 60),
            width: 400,
            height: 120
        )
        let element = CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Vellum",
                    fontSize: 64,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame
        )
        let content = makeContent(elements: [element])
        let rendered = try pixelBuffer(for: render(pageIndex: 0, content: content))
        let reference = try pixelBuffer(for: render(pageIndex: 0, content: makeContent()))

        XCTAssertGreaterThan(
            differingPixelCount(rendered, reference, in: cgRect(frame).insetBy(dx: 6, dy: 6)),
            0
        )
    }

    func testWrappedTextDrawsBelowItsPersistedFrame() throws {
        let frame = CanvasRect(x: 304, y: 478, width: 160, height: 44)
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
        let rendered = try pixelBuffer(
            for: render(pageIndex: 0, content: makeContent(elements: [element]))
        )
        let reference = try pixelBuffer(for: render(pageIndex: 0, content: makeContent()))
        let persistedFrame = cgRect(frame)
        let sampleRect = CGRect(
            x: persistedFrame.minX,
            y: persistedFrame.maxY,
            width: persistedFrame.width,
            height: 240
        )

        XCTAssertGreaterThan(
            differingPixelCount(rendered, reference, in: sampleRect),
            0
        )
    }

    func testWrappedTextGrowthIsTopAnchored() throws {
        let frame = CanvasRect(x: 304, y: 478, width: 160, height: 44)
        let textContent = TextBoxContent(
            text: "Vellum notes wrap across many narrow lines so every captured thought remains visible in a careful export.",
            fontSize: 32,
            color: CodableColor(red: 0, green: 0, blue: 0)
        )
        let element = CanvasElement(content: .text(textContent), frame: frame)
        let grownFrame = NotePageRenderer.growTextFrame(
            frame,
            textContent: textContent
        )
        let rendered = try pixelBuffer(
            for: render(pageIndex: 0, content: makeContent(elements: [element]))
        )
        let reference = try pixelBuffer(for: render(pageIndex: 0, content: makeContent()))
        let persistedFrame = cgRect(frame)
        let previousUpwardGrowth = CGFloat(grownFrame.height - frame.height) / 2
        let belowSampleRect = CGRect(
            x: persistedFrame.minX,
            y: persistedFrame.maxY,
            width: persistedFrame.width,
            height: 240
        )
        let aboveSampleRect = CGRect(
            x: persistedFrame.minX,
            y: persistedFrame.minY - previousUpwardGrowth,
            width: persistedFrame.width,
            height: previousUpwardGrowth - 4
        )

        XCTAssertGreaterThan(grownFrame.height, frame.height)
        XCTAssertEqual(grownFrame.y, frame.y, accuracy: 0.001)
        XCTAssertGreaterThan(previousUpwardGrowth, 4)
        XCTAssertGreaterThan(
            differingPixelCount(rendered, reference, in: belowSampleRect),
            0
        )
        XCTAssertEqual(
            differingPixelCount(rendered, reference, in: aboveSampleRect),
            0
        )
    }

    func testImageElementDrawsAspectFitImageInsideItsFrame() throws {
        let assetPath = "assets/red.png"
        let image = solidImage(color: .red, size: CGSize(width: 8, height: 4))
        let frame = CanvasRect(
            x: 250,
            y: Double(PageLayout.pageHeight / 2 - 100),
            width: 200,
            height: 200
        )
        let element = CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: assetPath,
                    originalPixelSize: CanvasSize(width: 8, height: 4)
                )
            ),
            frame: frame
        )
        let content = makeContent(
            elements: [element],
            imagesByAssetPath: [assetPath: image]
        )
        let pixels = try pixelBuffer(for: render(pageIndex: 0, content: content))
        let center = CGPoint(x: cgRect(frame).midX, y: cgRect(frame).midY)
        let pixel = pixels.pixel(atContentPoint: center)

        XCTAssertGreaterThanOrEqual(pixel.red, 250)
        XCTAssertLessThanOrEqual(pixel.green, 5)
        XCTAssertLessThanOrEqual(pixel.blue, 5)
        XCTAssertEqual(pixel.alpha, 255)
    }

    func testRotatedImageCrossingPageBoundaryDrawsOnSecondPage() throws {
        let assetPath = "assets/rotated-red.png"
        let centerY = PageLayout.pageHeight - 30
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
        let image = solidImage(color: .red, size: CGSize(width: 300, height: 40))
        let content = makeContent(
            elements: [element],
            imagesByAssetPath: [assetPath: image],
            pageCount: 2
        )
        let rendered = try pixelBuffer(for: render(pageIndex: 1, content: content))
        let reference = try pixelBuffer(
            for: render(pageIndex: 1, content: makeContent(pageCount: 2))
        )
        let overlap = element.rotatedBoundingBox.intersection(
            PageLayout.pageRect(index: 1)
        )
        let pageLocalOverlap = overlap.offsetBy(dx: 0, dy: -PageLayout.pageHeight)

        XCTAssertGreaterThan(
            differingPixelCount(rendered, reference, in: pageLocalOverlap),
            0
        )
    }

    func testEmptyContentRendersAtRequestedSize() throws {
        let pointSize = renderPointSize
        let image = NotePageRenderer.image(
            pageIndex: 0,
            content: makeContent(),
            pointSize: pointSize,
            scale: 1
        )

        XCTAssertEqual(image.size.width, pointSize.width, accuracy: 0.01)
        XCTAssertEqual(image.size.height, pointSize.height, accuracy: 1.0)
        XCTAssertNotNil(image.cgImage)
    }

    func testImageUsesRequestedPointSizeAndScale() throws {
        let pointSize = CGSize(width: 496, height: 701.5)
        let scale: CGFloat = 2
        let image = NotePageRenderer.image(
            pageIndex: 0,
            content: makeContent(),
            pointSize: pointSize,
            scale: scale
        )
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(image.size, pointSize)
        XCTAssertEqual(cgImage.width, Int(pointSize.width * scale))
        XCTAssertEqual(cgImage.height, Int(pointSize.height * scale))
    }

    private var renderPointSize: CGSize {
        let width: CGFloat = 192
        return CGSize(
            width: width,
            height: width * PageLayout.pageHeight / PageLayout.contentWidth
        )
    }

    private func render(
        pageIndex: Int,
        content: NotePageRenderer.Content
    ) -> UIImage {
        NotePageRenderer.image(
            pageIndex: pageIndex,
            content: content,
            pointSize: renderPointSize,
            scale: 1
        )
    }

    private func makeContent(
        drawing: PKDrawing = PKDrawing(),
        elements: [CanvasElement] = [],
        imagesByAssetPath: [String: UIImage] = [:],
        pageCount: Int = 1
    ) -> NotePageRenderer.Content {
        NotePageRenderer.Content(
            drawing: drawing,
            elements: elements,
            imagesByAssetPath: imagesByAssetPath,
            pageCount: pageCount
        )
    }

    private func makeStroke(
        locations: [CGPoint],
        size: CGSize
    ) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.1,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
    }

    private func solidImage(color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func pixelBuffer(for image: UIImage) throws -> PixelBuffer {
        let cgImage = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            )
        )
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )
        return PixelBuffer(width: cgImage.width, height: cgImage.height, bytes: bytes)
    }

    private func differingPixelCount(
        _ lhs: PixelBuffer,
        _ rhs: PixelBuffer,
        in contentRect: CGRect
    ) -> Int {
        XCTAssertEqual(lhs.width, rhs.width)
        XCTAssertEqual(lhs.height, rhs.height)

        let minX = max(
            0,
            Int(floor(contentRect.minX / PageLayout.contentWidth * CGFloat(lhs.width)))
        )
        let maxX = min(
            lhs.width,
            Int(ceil(contentRect.maxX / PageLayout.contentWidth * CGFloat(lhs.width)))
        )
        let minY = max(
            0,
            Int(floor(contentRect.minY / PageLayout.pageHeight * CGFloat(lhs.height)))
        )
        let maxY = min(
            lhs.height,
            Int(ceil(contentRect.maxY / PageLayout.pageHeight * CGFloat(lhs.height)))
        )

        var count = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                if lhs.pixel(x: x, y: y).differs(from: rhs.pixel(x: x, y: y)) {
                    count += 1
                }
            }
        }
        return count
    }

    private func cgRect(_ rect: CanvasRect) -> CGRect {
        CGRect(
            x: CGFloat(rect.x),
            y: CGFloat(rect.y),
            width: CGFloat(rect.width),
            height: CGFloat(rect.height)
        )
    }

    private struct PixelBuffer {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func pixel(atContentPoint point: CGPoint) -> Pixel {
            let x = min(
                width - 1,
                max(0, Int(point.x / PageLayout.contentWidth * CGFloat(width)))
            )
            let y = min(
                height - 1,
                max(0, Int(point.y / PageLayout.pageHeight * CGFloat(height)))
            )
            return pixel(x: x, y: y)
        }

        func pixel(x: Int, y: Int) -> Pixel {
            let offset = (y * width + x) * 4
            return Pixel(
                red: bytes[offset],
                green: bytes[offset + 1],
                blue: bytes[offset + 2],
                alpha: bytes[offset + 3]
            )
        }
    }

    private struct Pixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8

        func differs(from other: Pixel) -> Bool {
            abs(Int(red) - Int(other.red)) > 4
                || abs(Int(green) - Int(other.green)) > 4
                || abs(Int(blue) - Int(other.blue)) > 4
                || abs(Int(alpha) - Int(other.alpha)) > 4
        }
    }
}
