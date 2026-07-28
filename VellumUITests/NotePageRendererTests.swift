import Foundation
import PDFKit
import PencilKit
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class NotePageRendererTests: XCTestCase {
    func testInkIsCroppedToItsPage() throws {
        let relativeY = PageGeometry.a4.pageHeight / 2
        let absoluteY = PageGeometry.a4.pageHeight + relativeY
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
            y: Double(PageGeometry.a4.pageHeight / 2 - 60),
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
            y: Double(PageGeometry.a4.pageHeight / 2 - 100),
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
            PageGeometry.a4.pageRect(index: 1)
        )
        let pageLocalOverlap = overlap.offsetBy(dx: 0, dy: -PageGeometry.a4.pageHeight)

        XCTAssertGreaterThan(
            differingPixelCount(rendered, reference, in: pageLocalOverlap),
            0
        )
    }

    func testOpenPolylineShapeDrawsAlongItsDiagonal() throws {
        let frame = CanvasRect(x: 180, y: 220, width: 240, height: 180)
        let element = CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0),
                            CanvasPoint(x: 1, y: 1),
                        ],
                        isClosed: false
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 8
                )
            ),
            frame: frame
        )
        let rendered = try pixelBuffer(
            for: render(pageIndex: 0, content: makeContent(elements: [element]))
        )
        let reference = try pixelBuffer(for: render(pageIndex: 0, content: makeContent()))

        for point in [
            CGPoint(x: 240, y: 265),
            CGPoint(x: 300, y: 310),
            CGPoint(x: 360, y: 355),
        ] {
            let sampleRect = CGRect(
                x: point.x - 6,
                y: point.y - 6,
                width: 12,
                height: 12
            )
            XCTAssertGreaterThan(
                differingPixelCount(rendered, reference, in: sampleRect),
                0
            )
        }
    }

    func testClosedPolylineShapeDrawsAlongEveryEdge() throws {
        let frame = CanvasRect(x: 180, y: 220, width: 240, height: 160)
        let element = CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0),
                            CanvasPoint(x: 1, y: 0),
                            CanvasPoint(x: 1, y: 1),
                            CanvasPoint(x: 0, y: 1),
                        ],
                        isClosed: true
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 8
                )
            ),
            frame: frame
        )
        let rendered = try pixelBuffer(
            for: render(pageIndex: 0, content: makeContent(elements: [element]))
        )
        let reference = try pixelBuffer(for: render(pageIndex: 0, content: makeContent()))

        for point in [
            CGPoint(x: 300, y: 220),
            CGPoint(x: 420, y: 300),
            CGPoint(x: 300, y: 380),
            CGPoint(x: 180, y: 300),
        ] {
            let sampleRect = CGRect(
                x: point.x - 6,
                y: point.y - 6,
                width: 12,
                height: 12
            )
            XCTAssertGreaterThan(
                differingPixelCount(rendered, reference, in: sampleRect),
                0
            )
        }
    }

    func testRotatedEllipseShapeUsesTiltedBoundary() throws {
        let frame = CanvasRect(x: 250, y: 260, width: 240, height: 120)
        let rotation = Double.pi / 6
        let element = CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .ellipse,
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 8
                )
            ),
            frame: frame,
            rotation: rotation
        )
        let rendered = try pixelBuffer(
            for: render(pageIndex: 0, content: makeContent(elements: [element]))
        )
        let reference = try pixelBuffer(for: render(pageIndex: 0, content: makeContent()))
        let center = CGPoint(x: cgRect(frame).midX, y: cgRect(frame).midY)
        let radiusX = CGFloat(frame.width / 2)
        let tiltedRight = CGPoint(
            x: center.x + cos(CGFloat(rotation)) * radiusX,
            y: center.y + sin(CGFloat(rotation)) * radiusX
        )
        let untiltedRight = CGPoint(x: center.x + radiusX, y: center.y)

        XCTAssertGreaterThan(
            differingPixelCount(
                rendered,
                reference,
                in: CGRect(
                    x: tiltedRight.x - 6,
                    y: tiltedRight.y - 6,
                    width: 12,
                    height: 12
                )
            ),
            0
        )
        XCTAssertEqual(
            differingPixelCount(
                rendered,
                reference,
                in: CGRect(
                    x: untiltedRight.x - 3,
                    y: untiltedRight.y - 3,
                    width: 6,
                    height: 6
                )
            ),
            0
        )
    }

    func testThickShapeStrokeAtAPageBoundaryDrawsOnBothPages() throws {
        let boundary = PageGeometry.a4.pageHeight
        let strokeWidth: Double = 30
        let element = makeShapeEndingAtFirstPageBoundary(strokeWidth: strokeWidth)
        let content = makeContent(elements: [element], pageCount: 2)
        let emptyContent = makeContent(pageCount: 2)

        // The frame only touches the boundary, so the stroke's lower half is the whole
        // of page two's content -- and CGRect.intersects is false for touching rects.
        XCTAssertEqual(element.rotatedBoundingBox.maxY, boundary, accuracy: 0.001)
        XCTAssertFalse(
            element.rotatedBoundingBox.intersects(PageGeometry.a4.pageRect(index: 1))
        )

        let firstPage = try pixelBuffer(
            for: render(pageIndex: 0, content: content, pointSize: fullRenderPointSize)
        )
        let firstReference = try pixelBuffer(
            for: render(pageIndex: 0, content: emptyContent, pointSize: fullRenderPointSize)
        )
        let secondPage = try pixelBuffer(
            for: render(pageIndex: 1, content: content, pointSize: fullRenderPointSize)
        )
        let secondReference = try pixelBuffer(
            for: render(pageIndex: 1, content: emptyContent, pointSize: fullRenderPointSize)
        )
        let aboveBoundary = CGRect(x: 220, y: boundary - 16, width: 160, height: 12)
        let belowBoundary = CGRect(x: 220, y: 2, width: 160, height: 8)

        XCTAssertGreaterThan(
            differingPixelCount(firstPage, firstReference, in: aboveBoundary),
            0
        )
        XCTAssertGreaterThan(
            differingPixelCount(secondPage, secondReference, in: belowBoundary),
            0
        )
    }

    func testRotatedShapeStrokeReachingTheNextPageDrawsThere() throws {
        let boundary = PageGeometry.a4.pageHeight
        let strokeWidth: Double = 30
        let frame = CanvasRect(
            x: 200,
            y: Double(boundary) - 104,
            width: 200,
            height: 8
        )
        let element = CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0.5),
                            CanvasPoint(x: 1, y: 0.5),
                        ],
                        isClosed: false
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: strokeWidth
                )
            ),
            frame: frame,
            rotation: .pi / 2
        )
        let content = makeContent(elements: [element], pageCount: 2)
        let emptyContent = makeContent(pageCount: 2)

        // Rotation is what carries this shape down to the boundary: the unrotated frame
        // stops far above it, so inflating anything else would miss page two.
        XCTAssertEqual(element.rotatedBoundingBox.maxY, boundary, accuracy: 0.001)
        XCTAssertLessThan(
            cgRect(frame).maxY + CGFloat(strokeWidth) / 2,
            boundary
        )

        let secondPage = try pixelBuffer(
            for: render(pageIndex: 1, content: content, pointSize: fullRenderPointSize)
        )
        let secondReference = try pixelBuffer(
            for: render(pageIndex: 1, content: emptyContent, pointSize: fullRenderPointSize)
        )
        let belowBoundary = CGRect(x: 294, y: 1, width: 12, height: 8)

        XCTAssertGreaterThan(
            differingPixelCount(secondPage, secondReference, in: belowBoundary),
            0
        )
    }

    func testExportCountsThePageAShapeStrokeReachesInto() throws {
        let element = makeShapeEndingAtFirstPageBoundary(strokeWidth: 30)
        let output = try NoteExporter.export(
            content: makeContent(elements: [element]),
            title: "Boundary shape",
            format: .png
        )
        defer { try? FileManager.default.removeItem(at: output.directory) }

        XCTAssertEqual(
            element.rotatedBoundingBox.maxY,
            PageGeometry.a4.pageHeight,
            accuracy: 0.001
        )
        XCTAssertEqual(output.urls.count, 2)
        XCTAssertNotNil(UIImage(contentsOfFile: output.urls[1].path))
    }

    func testShapeAndInkRenderTogetherInOverlappingRegion() throws {
        let shape = CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0),
                            CanvasPoint(x: 1, y: 1),
                        ],
                        isClosed: false
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 8
                )
            ),
            frame: CanvasRect(x: 250, y: 300, width: 160, height: 160)
        )
        let stroke = makeStroke(
            locations: [
                CGPoint(x: 250, y: 460),
                CGPoint(x: 330, y: 380),
                CGPoint(x: 410, y: 300),
            ],
            size: CGSize(width: 12, height: 12)
        )
        let rendered = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    drawing: PKDrawing(strokes: [stroke]),
                    elements: [shape]
                )
            )
        )
        let reference = try pixelBuffer(for: render(pageIndex: 0, content: makeContent()))

        for point in [
            CGPoint(x: 270, y: 320),
            CGPoint(x: 330, y: 380),
        ] {
            XCTAssertGreaterThan(
                differingPixelCount(
                    rendered,
                    reference,
                    in: CGRect(
                        x: point.x - 6,
                        y: point.y - 6,
                        width: 12,
                        height: 12
                    )
                ),
                0
            )
        }
    }

    func testShapeStrokePixelsDifferBetweenLightAndDarkInterfaceStyles() throws {
        let center = CGPoint(
            x: PageLayout.contentWidth / 2,
            y: PageGeometry.a4.pageHeight / 2
        )
        let shape = makeHorizontalShape(
            strokeColor: ToolPreferences.default.pen.color,
            strokeWidth: 28
        )
        let paperStyle = PageBackgroundStyle(
            kind: .blank,
            paperTint: CodableColor(red: 0.4, green: 0.4, blue: 0.4)
        )
        let lightPixels = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    elements: [shape],
                    style: paperStyle,
                    interfaceStyle: .light
                ),
                pointSize: fullRenderPointSize
            )
        )
        let darkPixels = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    elements: [shape],
                    style: paperStyle,
                    interfaceStyle: .dark
                ),
                pointSize: fullRenderPointSize
            )
        )
        let strokeSampleRect = CGRect(
            x: center.x - 40,
            y: center.y - 12,
            width: 80,
            height: 24
        )

        XCTAssertGreaterThan(
            differingPixelCount(lightPixels, darkPixels, in: strokeSampleRect),
            0
        )
        XCTAssertTrue(
            lightPixels.pixel(atContentPoint: center).differs(
                from: darkPixels.pixel(atContentPoint: center)
            )
        )
    }

    func testDarkInterfaceStyleRendersDefaultPenShapeLighterThanPaper() throws {
        let center = CGPoint(
            x: PageLayout.contentWidth / 2,
            y: PageGeometry.a4.pageHeight / 2
        )
        let paperPixels = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(style: .blank, interfaceStyle: .dark),
                pointSize: fullRenderPointSize
            )
        )
        let shapePixels = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    elements: [
                        makeHorizontalShape(
                            strokeColor: ToolPreferences.default.pen.color,
                            strokeWidth: 28
                        ),
                    ],
                    style: .blank,
                    interfaceStyle: .dark
                ),
                pointSize: fullRenderPointSize
            )
        )
        let paperPixel = paperPixels.pixel(atContentPoint: center)
        let shapePixel = shapePixels.pixel(atContentPoint: center)

        XCTAssertTrue(shapePixel.differs(from: paperPixel))
        XCTAssertGreaterThan(shapePixel.luminance, paperPixel.luminance)
    }

    func testDarkInterfaceStylePreservesTranslucentShapeAlpha() throws {
        let center = CGPoint(
            x: PageLayout.contentWidth / 2,
            y: PageGeometry.a4.pageHeight / 2
        )
        let markerColor = ToolPreferences.default.highlighter.color
        let translucentShape = makeHorizontalShape(
            strokeColor: CodableColor(
                red: markerColor.red,
                green: markerColor.green,
                blue: markerColor.blue,
                alpha: 0.55
            ),
            strokeWidth: 32
        )
        let opaqueShape = makeHorizontalShape(
            strokeColor: CodableColor(
                red: markerColor.red,
                green: markerColor.green,
                blue: markerColor.blue
            ),
            strokeWidth: 32
        )
        let paper = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(style: .blank, interfaceStyle: .dark),
                pointSize: fullRenderPointSize
            )
        )
        let translucent = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    elements: [translucentShape],
                    style: .blank,
                    interfaceStyle: .dark
                ),
                pointSize: fullRenderPointSize
            )
        )
        let opaque = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    elements: [opaqueShape],
                    style: .blank,
                    interfaceStyle: .dark
                ),
                pointSize: fullRenderPointSize
            )
        )
        let paperPixel = paper.pixel(atContentPoint: center)
        let translucentPixel = translucent.pixel(atContentPoint: center)
        let opaquePixel = opaque.pixel(atContentPoint: center)

        XCTAssertTrue(translucentPixel.differs(from: paperPixel))
        XCTAssertTrue(translucentPixel.differs(from: opaquePixel))
        XCTAssertGreaterThan(translucentPixel.luminance, paperPixel.luminance)
        XCTAssertLessThan(translucentPixel.luminance, opaquePixel.luminance)
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

    func testRuledStyleRendersHorizontalLinesAtSpacingIntervals() throws {
        let spacing: Double = 32
        let rendered = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: PageBackgroundStyle(kind: .ruled, spacing: spacing)
                ),
                pointSize: fullRenderPointSize
            )
        )
        let reference = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: PageBackgroundStyle(kind: .blank, spacing: spacing)
                ),
                pointSize: fullRenderPointSize
            )
        )
        let lineRect = CGRect(x: 96, y: 30, width: 576, height: 4)
        let betweenLinesRect = CGRect(x: 96, y: 46, width: 576, height: 4)

        XCTAssertGreaterThan(
            differingPixelCount(rendered, reference, in: lineRect),
            0
        )
        XCTAssertEqual(
            differingPixelCount(rendered, reference, in: betweenLinesRect),
            0
        )
    }

    func testGridStyleRendersHorizontalAndVerticalLines() throws {
        let spacing: Double = 32
        let rendered = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: PageBackgroundStyle(kind: .grid, spacing: spacing)
                ),
                pointSize: fullRenderPointSize
            )
        )
        let reference = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: PageBackgroundStyle(kind: .blank, spacing: spacing)
                ),
                pointSize: fullRenderPointSize
            )
        )
        let horizontalLineRect = CGRect(x: 78, y: 30, width: 4, height: 4)
        let verticalLineRect = CGRect(x: 30, y: 78, width: 4, height: 4)

        XCTAssertGreaterThan(
            differingPixelCount(rendered, reference, in: horizontalLineRect),
            0
        )
        XCTAssertGreaterThan(
            differingPixelCount(rendered, reference, in: verticalLineRect),
            0
        )
    }

    func testBlankStyleRendersNoPattern() throws {
        let blank = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(style: .blank),
                pointSize: fullRenderPointSize
            )
        )
        let dots = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(),
                pointSize: fullRenderPointSize
            )
        )
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let paperColor = UIColor(VellumTheme.card).resolvedColor(with: traits)
        let plainPaper = try pixelBuffer(
            for: solidImage(color: paperColor, size: fullRenderPointSize)
        )
        let dotRect = CGRect(x: 22, y: 22, width: 4, height: 4)

        XCTAssertGreaterThan(
            differingPixelCount(dots, plainPaper, in: dotRect),
            0
        )
        XCTAssertEqual(
            differingPixelCount(blank, plainPaper, in: dotRect),
            0
        )
    }

    func testCustomPaperTintFillsTheSheetWithThatColor() throws {
        let tint = CodableColor(red: 0.2, green: 0.4, blue: 0.8)
        let pixels = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: PageBackgroundStyle(kind: .blank, paperTint: tint)
                ),
                pointSize: fullRenderPointSize
            )
        )
        let pixel = pixels.pixel(
            atContentPoint: CGPoint(
                x: PageLayout.contentWidth / 2,
                y: PageGeometry.a4.pageHeight / 2
            )
        )

        XCTAssertEqual(CGFloat(pixel.red), CGFloat(tint.red * 255), accuracy: 4)
        XCTAssertEqual(CGFloat(pixel.green), CGFloat(tint.green * 255), accuracy: 4)
        XCTAssertEqual(CGFloat(pixel.blue), CGFloat(tint.blue * 255), accuracy: 4)
        XCTAssertEqual(pixel.alpha, 255)
    }

    func testDarkPaperTintUsesLightPatternInk() throws {
        let tint = CodableColor(hex: "#23201A")
        let dots = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: PageBackgroundStyle(kind: .dots, paperTint: tint)
                ),
                pointSize: fullRenderPointSize
            )
        )
        let blank = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: PageBackgroundStyle(kind: .blank, paperTint: tint)
                ),
                pointSize: fullRenderPointSize
            )
        )
        let dotPoint = CGPoint(x: 24, y: 24)
        let dotPixel = dots.pixel(atContentPoint: dotPoint)
        let backgroundPixel = blank.pixel(atContentPoint: dotPoint)

        XCTAssertGreaterThan(dotPixel.red, backgroundPixel.red)
        XCTAssertGreaterThan(dotPixel.green, backgroundPixel.green)
        XCTAssertGreaterThan(dotPixel.blue, backgroundPixel.blue)
        XCTAssertGreaterThan(
            differingPixelCount(
                dots,
                blank,
                in: CGRect(x: 22, y: 22, width: 4, height: 4)
            ),
            0
        )
    }

    func testSecondPageDotsAlignToThePageOrigin() throws {
        let pageRect = PageGeometry.a4.pageRect(index: 1)
        let spacing = CGFloat(PageBackgroundStyle.legacyDefault.spacing)
        let absoluteDotY = pageRect.minY + spacing
        let pageLocalDotY = absoluteDotY - pageRect.minY
        let rendered = try pixelBuffer(
            for: render(
                pageIndex: 1,
                content: makeContent(pageCount: 2),
                pointSize: fullRenderPointSize
            )
        )
        let reference = try pixelBuffer(
            for: render(
                pageIndex: 1,
                content: makeContent(
                    pageCount: 2,
                    style: .blank
                ),
                pointSize: fullRenderPointSize
            )
        )
        let dotRect = CGRect(
            x: spacing - 2,
            y: pageLocalDotY - 2,
            width: 4,
            height: 4
        )

        XCTAssertEqual(pageRect.minY, PageGeometry.a4.pageHeight, accuracy: 0.001)
        XCTAssertEqual(pageLocalDotY, spacing, accuracy: 0.001)
        XCTAssertGreaterThan(
            differingPixelCount(rendered, reference, in: dotRect),
            0
        )
    }

    func testPDFPageRendersAspectFitWithPaperLetterboxingAndLeavesOtherBandsUnchanged()
        throws {
        let sourceSize = CGSize(width: 320, height: 320)
        let pdfDocument = try makeSolidPDFDocument(color: .blue, size: sourceSize)
        let pdfPage = try XCTUnwrap(pdfDocument.page(at: 0))
        let content = makeContent(
            pageCount: 2,
            style: .blank,
            pdfPagesByBand: [0: pdfPage]
        )
        let renderedPDFBand = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: content,
                pointSize: fullRenderPointSize
            )
        )
        let blankContent = makeContent(pageCount: 2, style: .blank)
        let blankFirstBand = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: blankContent,
                pointSize: fullRenderPointSize
            )
        )
        let fittedRect = PageGeometry.a4.fittedRect(
            forSourcePageSize: sourceSize,
            pageIndex: 0
        )
        let pdfPixel = renderedPDFBand.pixel(atContentPoint: CGPoint(
            x: fittedRect.midX,
            y: fittedRect.midY
        ))
        let marginPoint = CGPoint(
            x: PageLayout.contentWidth / 2,
            y: fittedRect.minY / 2
        )
        let marginPixel = renderedPDFBand.pixel(atContentPoint: marginPoint)
        let paperPixel = blankFirstBand.pixel(atContentPoint: marginPoint)

        XCTAssertLessThanOrEqual(pdfPixel.red, 8)
        XCTAssertLessThanOrEqual(pdfPixel.green, 8)
        XCTAssertGreaterThanOrEqual(pdfPixel.blue, 230)
        XCTAssertFalse(marginPixel.differs(from: paperPixel))
        XCTAssertTrue(marginPixel.differs(from: pdfPixel))

        let renderedNonPDFBand = try pixelBuffer(
            for: render(
                pageIndex: 1,
                content: content,
                pointSize: fullRenderPointSize
            )
        )
        let referenceNonPDFBand = try pixelBuffer(
            for: render(
                pageIndex: 1,
                content: blankContent,
                pointSize: fullRenderPointSize
            )
        )
        XCTAssertEqual(
            differingPixelCount(
                renderedNonPDFBand,
                referenceNonPDFBand,
                in: CGRect(origin: .zero, size: fullRenderPointSize)
            ),
            0
        )
    }

    func testLetterGeometryFillsTheFormerA4LetterboxMarginWithPDFContent() throws {
        let geometry = PageGeometry(aspectRatio: 792.0 / 612.0)
        let sourceSize = CGSize(width: 612, height: 792)
        let pdfDocument = try makeSolidPDFDocument(color: .white, size: sourceSize)
        let pdfPage = try XCTUnwrap(pdfDocument.page(at: 0))
        let tintedPaper = PageBackgroundStyle(
            kind: .blank,
            paperTint: CodableColor(red: 0.55, green: 0.35, blue: 0.2)
        )
        let pointSize = CGSize(
            width: geometry.contentWidth,
            height: geometry.pageHeight
        )
        let rendered = try pixelBuffer(
            for: renderVector(
                pageIndex: 0,
                content: makeContent(
                    geometry: geometry,
                    style: tintedPaper,
                    pdfPagesByBand: [0: pdfPage]
                ),
                pointSize: pointSize
            )
        )
        let reference = try pixelBuffer(
            for: renderVector(
                pageIndex: 0,
                content: makeContent(
                    geometry: geometry,
                    style: tintedPaper
                ),
                pointSize: pointSize
            )
        )
        let oldA4FittedRect = PageGeometry.a4.fittedRect(
            forSourcePageSize: sourceSize,
            pageIndex: 0
        )
        let probePoint = CGPoint(x: geometry.contentWidth / 2, y: 20)
        let x = Int(probePoint.x)
        let y = Int(probePoint.y)
        let pdfPixel = rendered.pixel(x: x, y: y)
        let paperPixel = reference.pixel(x: x, y: y)

        XCTAssertLessThan(probePoint.y, oldA4FittedRect.minY)
        XCTAssertTrue(pdfPixel.differs(from: paperPixel))
        XCTAssertGreaterThanOrEqual(pdfPixel.red, 245)
        XCTAssertGreaterThanOrEqual(pdfPixel.green, 245)
        XCTAssertGreaterThanOrEqual(pdfPixel.blue, 245)
    }

    func testWhitePDFOverBlankPaperInLightModeIsPixelIdenticalToPaper() throws {
        let sourceSize = CGSize(width: 320, height: 320)
        let pdfDocument = try makeSolidPDFDocument(color: .white, size: sourceSize)
        let pdfPage = try XCTUnwrap(pdfDocument.page(at: 0))
        let rendered = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: .blank,
                    pdfPagesByBand: [0: pdfPage]
                ),
                pointSize: fullRenderPointSize
            )
        )
        let reference = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(style: .blank),
                pointSize: fullRenderPointSize
            )
        )
        let fittedRect = PageGeometry.a4.fittedRect(
            forSourcePageSize: sourceSize,
            pageIndex: 0
        ).insetBy(dx: 16, dy: 16)

        XCTAssertEqual(
            differingPixelCount(rendered, reference, in: fittedRect),
            0
        )
    }

    func testDarkInterfaceStyleRendersDarkCardPaperAndLightInk() throws {
        let center = CGPoint(
            x: PageLayout.contentWidth / 2,
            y: PageGeometry.a4.pageHeight / 2
        )
        let paperContent = makeContent(style: .blank, interfaceStyle: .dark)
        let paperPixels = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: paperContent,
                pointSize: fullRenderPointSize
            )
        )
        let paperPixel = paperPixels.pixel(atContentPoint: center)

        XCTAssertEqual(CGFloat(paperPixel.red), 0x24, accuracy: 10)
        XCTAssertEqual(CGFloat(paperPixel.green), 0x20, accuracy: 10)
        XCTAssertEqual(CGFloat(paperPixel.blue), 0x19, accuracy: 10)

        let stroke = makeStroke(
            locations: [
                CGPoint(x: center.x - 40, y: center.y),
                center,
                CGPoint(x: center.x + 40, y: center.y),
            ],
            size: CGSize(width: 28, height: 28)
        )
        let inkPixels = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    drawing: PKDrawing(strokes: [stroke]),
                    style: .blank,
                    interfaceStyle: .dark
                ),
                pointSize: fullRenderPointSize
            )
        )
        let inkPixel = inkPixels.pixel(atContentPoint: center)

        XCTAssertGreaterThan(inkPixel.red, paperPixel.red)
    }

    func testWhitePDFInDarkModeApproximatesDarkCardPaper() throws {
        let sourceSize = CGSize(width: 320, height: 320)
        let pdfDocument = try makeSolidPDFDocument(color: .white, size: sourceSize)
        let pdfPage = try XCTUnwrap(pdfDocument.page(at: 0))
        let rendered = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: .blank,
                    interfaceStyle: .dark,
                    pdfPagesByBand: [0: pdfPage]
                ),
                pointSize: fullRenderPointSize
            )
        )
        let reference = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: .blank,
                    interfaceStyle: .dark
                ),
                pointSize: fullRenderPointSize
            )
        )
        let fittedRect = PageGeometry.a4.fittedRect(
            forSourcePageSize: sourceSize,
            pageIndex: 0
        )
        let sampleRect = CGRect(
            x: fittedRect.midX - 8,
            y: fittedRect.midY - 8,
            width: 16,
            height: 16
        )

        XCTAssertEqual(
            differingPixelCount(rendered, reference, in: sampleRect),
            0
        )
    }

    func testBluePDFInDarkModeKeepsBlueChannelDominant() throws {
        let sourceSize = CGSize(width: 320, height: 320)
        let pdfDocument = try makeSolidPDFDocument(color: .blue, size: sourceSize)
        let pdfPage = try XCTUnwrap(pdfDocument.page(at: 0))
        let rendered = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: makeContent(
                    style: .blank,
                    interfaceStyle: .dark,
                    pdfPagesByBand: [0: pdfPage]
                ),
                pointSize: fullRenderPointSize
            )
        )
        let fittedRect = PageGeometry.a4.fittedRect(
            forSourcePageSize: sourceSize,
            pageIndex: 0
        )
        let pixel = rendered.pixel(atContentPoint: CGPoint(
            x: fittedRect.midX,
            y: fittedRect.midY
        ))

        XCTAssertGreaterThan(pixel.blue, pixel.red)
        XCTAssertGreaterThan(pixel.blue, pixel.green)
    }

    func testVectorTreatmentStillYieldsFullBlueForExport() throws {
        let sourceSize = CGSize(width: 320, height: 320)
        let pdfDocument = try makeSolidPDFDocument(color: .blue, size: sourceSize)
        let pdfPage = try XCTUnwrap(pdfDocument.page(at: 0))
        let rendered = try pixelBuffer(
            for: renderVector(
                pageIndex: 0,
                content: makeContent(
                    style: .blank,
                    pdfPagesByBand: [0: pdfPage]
                ),
                pointSize: fullRenderPointSize
            )
        )
        let fittedRect = PageGeometry.a4.fittedRect(
            forSourcePageSize: sourceSize,
            pageIndex: 0
        )
        let pixel = rendered.pixel(atContentPoint: CGPoint(
            x: fittedRect.midX,
            y: fittedRect.midY
        ))

        XCTAssertLessThanOrEqual(pixel.red, 8)
        XCTAssertLessThanOrEqual(pixel.green, 8)
        XCTAssertGreaterThanOrEqual(pixel.blue, 247)
    }

    func testInkCompositesAbovePDFPage() throws {
        let pdfDocument = try makeSolidPDFDocument(
            color: .blue,
            size: CGSize(width: 320, height: 320)
        )
        let pdfPage = try XCTUnwrap(pdfDocument.page(at: 0))
        let center = CGPoint(
            x: PageLayout.contentWidth / 2,
            y: PageGeometry.a4.pageHeight / 2
        )
        let stroke = makeStroke(
            locations: [
                CGPoint(x: center.x - 40, y: center.y),
                center,
                CGPoint(x: center.x + 40, y: center.y),
            ],
            size: CGSize(width: 28, height: 28)
        )
        let pdfOnly = makeContent(
            style: .blank,
            pdfPagesByBand: [0: pdfPage]
        )
        let withInk = makeContent(
            drawing: PKDrawing(strokes: [stroke]),
            style: .blank,
            pdfPagesByBand: [0: pdfPage]
        )
        let pdfOnlyPixels = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: pdfOnly,
                pointSize: fullRenderPointSize
            )
        )
        let withInkPixels = try pixelBuffer(
            for: render(
                pageIndex: 0,
                content: withInk,
                pointSize: fullRenderPointSize
            )
        )

        XCTAssertTrue(
            withInkPixels.pixel(atContentPoint: center).differs(
                from: pdfOnlyPixels.pixel(atContentPoint: center)
            )
        )
        XCTAssertGreaterThan(
            differingPixelCount(
                withInkPixels,
                pdfOnlyPixels,
                in: CGRect(x: center.x - 48, y: center.y - 20, width: 96, height: 40)
            ),
            0
        )
    }

    private func renderVector(
        pageIndex: Int,
        content: NotePageRenderer.Content,
        pointSize: CGSize
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pointSize, format: format).image { context in
            let pointScale = pointSize.width / PageLayout.contentWidth
            context.cgContext.scaleBy(x: pointScale, y: pointScale)
            NotePageRenderer.draw(
                pageIndex: pageIndex,
                content: content,
                pdfBandTreatment: .vector,
                in: context.cgContext
            )
        }
    }

    private var renderPointSize: CGSize {
        let width: CGFloat = 192
        return CGSize(
            width: width,
            height: width * PageGeometry.a4.pageHeight / PageLayout.contentWidth
        )
    }

    private var fullRenderPointSize: CGSize {
        CGSize(width: PageLayout.contentWidth, height: PageGeometry.a4.pageHeight)
    }

    private func render(
        pageIndex: Int,
        content: NotePageRenderer.Content,
        pointSize: CGSize? = nil
    ) -> UIImage {
        NotePageRenderer.image(
            pageIndex: pageIndex,
            content: content,
            pointSize: pointSize ?? renderPointSize,
            scale: 1
        )
    }

    private func makeContent(
        drawing: PKDrawing = PKDrawing(),
        elements: [CanvasElement] = [],
        imagesByAssetPath: [String: UIImage] = [:],
        pageCount: Int = 1,
        geometry: PageGeometry = .a4,
        style: PageBackgroundStyle = .legacyDefault,
        interfaceStyle: UIUserInterfaceStyle = .light,
        pdfPagesByBand: [Int: PDFPage] = [:]
    ) -> NotePageRenderer.Content {
        NotePageRenderer.Content(
            drawing: drawing,
            elements: elements,
            imagesByAssetPath: imagesByAssetPath,
            pageCount: pageCount,
            geometry: geometry,
            style: style,
            interfaceStyle: interfaceStyle,
            pdfPagesByBand: pdfPagesByBand
        )
    }

    private func makeSolidPDFDocument(
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

    private func makeHorizontalShape(
        strokeColor: CodableColor,
        strokeWidth: Double
    ) -> CanvasElement {
        let center = CGPoint(
            x: PageLayout.contentWidth / 2,
            y: PageGeometry.a4.pageHeight / 2
        )
        return CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0.5),
                            CanvasPoint(x: 1, y: 0.5),
                        ],
                        isClosed: false
                    ),
                    strokeColor: strokeColor,
                    strokeWidth: strokeWidth
                )
            ),
            frame: CanvasRect(
                x: Double(center.x - 100),
                y: Double(center.y - 40),
                width: 200,
                height: 80
            )
        )
    }

    /// A thick horizontal line whose frame -- the recognizer's minimum-height frame for a
    /// straight line -- ends exactly at the first page boundary, so only ink overhangs it.
    private func makeShapeEndingAtFirstPageBoundary(
        strokeWidth: Double
    ) -> CanvasElement {
        CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0.5),
                            CanvasPoint(x: 1, y: 0.5),
                        ],
                        isClosed: false
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: strokeWidth
                )
            ),
            frame: CanvasRect(
                x: 200,
                y: Double(PageGeometry.a4.pageHeight)
                    - ShapeElementBuilder.minimumFrameExtent,
                width: 200,
                height: ShapeElementBuilder.minimumFrameExtent
            )
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
            Int(floor(contentRect.minY / PageGeometry.a4.pageHeight * CGFloat(lhs.height)))
        )
        let maxY = min(
            lhs.height,
            Int(ceil(contentRect.maxY / PageGeometry.a4.pageHeight * CGFloat(lhs.height)))
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

    private struct Pixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8

        var luminance: Double {
            0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
        }

        func differs(from other: Pixel) -> Bool {
            abs(Int(red) - Int(other.red)) > 4
                || abs(Int(green) - Int(other.green)) > 4
                || abs(Int(blue) - Int(other.blue)) > 4
                || abs(Int(alpha) - Int(other.alpha)) > 4
        }
    }
}
