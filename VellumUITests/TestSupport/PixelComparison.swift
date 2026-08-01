import CoreGraphics
import Foundation
import PDFKit
import UIKit
import VellumCore
import XCTest

/// Image-diff machinery for the render tests.
///
/// These comparisons are the only coverage the PDF-export and page-thumbnail render paths have,
/// so the sources are deliberately flat: solid fills and solid single-page PDFs, whose expected
/// output a test can state exactly.
enum PixelComparison {
    static func solidImage(color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func makeSolidPDFDocument(
        color: UIColor,
        size: CGSize
    ) throws -> PDFDocument {
        let bounds = CGRect(origin: .zero, size: size)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fill(bounds)
        }
        return try XCTUnwrap(PDFDocument(data: data))
    }

    /// Redraws `image` into a known 8-bit RGBA layout so pixels can be read by offset —
    /// a `UIImage` gives no guarantee about the backing store's format.
    static func pixelBuffer(for image: UIImage) throws -> PixelBuffer {
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

    /// Counts differing pixels inside `contentRect`, which is given in page content
    /// coordinates and scaled to whatever resolution the two buffers were rendered at.
    static func differingPixelCount(
        _ lhs: PixelBuffer,
        _ rhs: PixelBuffer,
        in contentRect: CGRect
    ) -> Int {
        XCTAssertEqual(lhs.width, rhs.width)
        XCTAssertEqual(lhs.height, rhs.height)

        let minX = max(
            0,
            Int(floor(contentRect.minX / PageLayout.portraitContentWidth * CGFloat(lhs.width)))
        )
        let maxX = min(
            lhs.width,
            Int(ceil(contentRect.maxX / PageLayout.portraitContentWidth * CGFloat(lhs.width)))
        )
        let minY = max(
            0,
            Int(floor(contentRect.minY / PageGeometry.a4.pageHeight * CGFloat(lhs.height)))
        )
        let maxY = min(
            lhs.height,
            Int(ceil(contentRect.maxY / PageGeometry.a4.pageHeight * CGFloat(lhs.height)))
        )

        var count = 0
        for y in minY..<maxY {
            for x in minX..<maxX where lhs.pixel(x: x, y: y).differs(
                from: rhs.pixel(x: x, y: y)
            ) {
                count += 1
            }
        }
        return count
    }

    static func cgRect(_ rect: CanvasRect) -> CGRect {
        CGRect(
            x: CGFloat(rect.x),
            y: CGFloat(rect.y),
            width: CGFloat(rect.width),
            height: CGFloat(rect.height)
        )
    }
}

struct PixelBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// Looks up the pixel covering a point in page content coordinates, clamped to the buffer.
    func pixel(atContentPoint point: CGPoint) -> Pixel {
        let x = min(
            width - 1,
            max(0, Int(point.x / PageLayout.portraitContentWidth * CGFloat(width)))
        )
        let y = min(
            height - 1,
            max(0, Int(point.y / PageGeometry.a4.pageHeight * CGFloat(height)))
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

struct Pixel {
    /// Per-channel slack, in 8-bit levels, absorbing the rounding two render passes disagree
    /// on. Raising it hides real regressions; the render tests are calibrated against it.
    static let colorTolerance = 4

    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    var luminance: Double {
        0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
    }

    func differs(from other: Pixel) -> Bool {
        abs(Int(red) - Int(other.red)) > Self.colorTolerance
            || abs(Int(green) - Int(other.green)) > Self.colorTolerance
            || abs(Int(blue) - Int(other.blue)) > Self.colorTolerance
            || abs(Int(alpha) - Int(other.alpha)) > Self.colorTolerance
    }
}
