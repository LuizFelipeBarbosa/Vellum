import PDFKit
import PencilKit
import SwiftUI
import UIKit
import VellumCore

enum NotePageRenderer {
    /// A render snapshot crosses to a serial background actor. Its UIKit,
    /// PencilKit, and PDFKit references are treated as immutable while rendering.
    struct Content: @unchecked Sendable {
        var drawing: PKDrawing
        var elements: [CanvasElement]
        var imagesByAssetPath: [String: UIImage]
        var pageCount: Int
        var geometry: PageGeometry = .a4
        var style: PageBackgroundStyle = .legacyDefault
        var interfaceStyle: UIUserInterfaceStyle = .light
        var pdfPagesByBand: [Int: PDFPage] = [:]
        var pdfExpectedBands: Set<Int> = []
    }

    enum PDFBandTreatment {
        case vector
        case blendedRaster
    }

    /// Draws page `pageIndex` into `ctx`, whose coordinate space is content points
    /// with the origin at the page's top-left.
    static func draw(
        pageIndex: Int,
        content: Content,
        pdfBandTreatment: PDFBandTreatment = .vector,
        in ctx: CGContext
    ) {
        let pageRect = content.geometry.pageRect(index: pageIndex)
        let pageBounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: content.geometry.contentWidth,
                height: content.geometry.pageHeight
            )
        )

        ctx.saveGState()
        defer { ctx.restoreGState() }

        let pdfPage = content.pdfPagesByBand[pageIndex]
        drawPaper(
            pageRect: pageRect,
            pageBounds: pageBounds,
            style: content.style,
            interfaceStyle: content.interfaceStyle,
            drawsPattern: pdfPage == nil,
            in: ctx
        )

        if let pdfPage {
            switch pdfBandTreatment {
            case .vector:
                drawPDFPage(
                    pdfPage,
                    pageIndex: pageIndex,
                    pageRect: pageRect,
                    pageBounds: pageBounds,
                    geometry: content.geometry,
                    in: ctx
                )
            case .blendedRaster:
                drawBlendedRasterPDFPage(
                    pdfPage,
                    pageIndex: pageIndex,
                    pageRect: pageRect,
                    pageBounds: pageBounds,
                    geometry: content.geometry,
                    interfaceStyle: content.interfaceStyle,
                    in: ctx
                )
            }
        }

        for element in content.elements {
            guard case .image(let imageContent) = element.content else { continue }
            drawImage(
                imageContent,
                for: element,
                pageRect: pageRect,
                pageBounds: pageBounds,
                imagesByAssetPath: content.imagesByAssetPath,
                in: ctx
            )
        }

        for element in content.elements {
            guard case .shape(let shapeContent) = element.content else { continue }
            drawShape(
                shapeContent,
                for: element,
                pageRect: pageRect,
                pageBounds: pageBounds,
                interfaceStyle: content.interfaceStyle,
                in: ctx
            )
        }

        drawInk(
            content.drawing,
            pageRect: pageRect,
            pageBounds: pageBounds,
            interfaceStyle: content.interfaceStyle,
            in: ctx
        )

        for element in content.elements {
            guard case .text(let textContent) = element.content else { continue }
            drawText(
                textContent,
                for: element,
                pageRect: pageRect,
                pageBounds: pageBounds,
                in: ctx
            )
        }
    }

    /// Convenience rendering for one page at the provided point size and scale.
    static func image(
        pageIndex: Int,
        content: Content,
        pointSize: CGSize,
        scale: CGFloat
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)

        return renderer.image { rendererContext in
            let pointScale = pointSize.width / content.geometry.contentWidth
            rendererContext.cgContext.scaleBy(x: pointScale, y: pointScale)
            draw(
                pageIndex: pageIndex,
                content: content,
                pdfBandTreatment: .blendedRaster,
                in: rendererContext.cgContext
            )
        }
    }

    private static func drawPaper(
        pageRect: CGRect,
        pageBounds: CGRect,
        style: PageBackgroundStyle,
        interfaceStyle: UIUserInterfaceStyle,
        drawsPattern: Bool,
        in ctx: CGContext
    ) {
        let paperColor: UIColor
        let patternColor: UIColor
        if let tint = style.paperTint {
            paperColor = UIColor(
                red: CGFloat(tint.red),
                green: CGFloat(tint.green),
                blue: CGFloat(tint.blue),
                alpha: CGFloat(tint.alpha)
            )
            let ink = PageBackgroundStyle.patternInk(forTint: tint, opacity: 0.12)
            patternColor = UIColor(
                red: CGFloat(ink.red),
                green: CGFloat(ink.green),
                blue: CGFloat(ink.blue),
                alpha: CGFloat(ink.alpha)
            )
        } else {
            let traits = UITraitCollection(userInterfaceStyle: interfaceStyle)
            paperColor = UIColor(VellumTheme.card).resolvedColor(with: traits)
            patternColor = UIColor(VellumTheme.ink)
                .resolvedColor(with: traits)
                .withAlphaComponent(0.12)
        }

        ctx.setFillColor(paperColor.cgColor)
        ctx.fill(pageBounds)

        guard drawsPattern else { return }

        switch style.kind {
        case .blank:
            break
        case .dots:
            let xs = PageBackgroundPattern.dotXs(
                style: style,
                pageRect: pageRect,
                clippedTo: pageRect
            )
            let ys = PageBackgroundPattern.dotYs(
                style: style,
                pageRect: pageRect,
                clippedTo: pageRect
            )
            let radius: CGFloat = 1
            let path = CGMutablePath()

            for x in xs.values {
                for y in ys.values {
                    path.addEllipse(
                        in: CGRect(
                            x: x - radius,
                            y: y - pageRect.minY - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                    )
                }
            }

            ctx.setFillColor(patternColor.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        case .ruled, .grid:
            let ys = PageBackgroundPattern.ruleYs(
                style: style,
                pageRect: pageRect,
                clippedTo: pageRect
            )
            let path = CGMutablePath()

            for y in ys.values {
                let localY = y - pageRect.minY
                path.move(to: CGPoint(x: 0, y: localY))
                path.addLine(to: CGPoint(x: pageBounds.width, y: localY))
            }

            if style.kind == .grid {
                let xs = PageBackgroundPattern.gridXs(
                    style: style,
                    pageRect: pageRect,
                    clippedTo: pageRect
                )
                for x in xs.values {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: pageBounds.height))
                }
            }

            ctx.setStrokeColor(patternColor.cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private static func drawPDFPage(
        _ page: PDFPage,
        pageIndex: Int,
        pageRect: CGRect,
        pageBounds: CGRect,
        geometry: PageGeometry,
        in ctx: CGContext
    ) {
        guard let pageRef = page.pageRef else { return }

        let displayedSize = displayedMediaBoxSize(for: page)
        // This flip is symmetric only because geometry.fittedRect centers the
        // PDF vertically. A top-anchored fit would not match PdfPagesLayer.
        let fittedRect = geometry.fittedRect(
            forSourcePageSize: displayedSize,
            pageIndex: pageIndex
        ).offsetBy(dx: 0, dy: -pageRect.minY)

        ctx.saveGState()
        ctx.clip(to: pageBounds)
        ctx.translateBy(x: 0, y: pageBounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.concatenate(
            pdfDrawingTransform(
                for: pageRef,
                displayedMediaBoxSize: displayedSize,
                fittingInto: fittedRect
            )
        )
        ctx.drawPDFPage(pageRef)
        ctx.restoreGState()
    }

    private static func drawBlendedRasterPDFPage(
        _ page: PDFPage,
        pageIndex: Int,
        pageRect: CGRect,
        pageBounds: CGRect,
        geometry: PageGeometry,
        interfaceStyle: UIUserInterfaceStyle,
        in ctx: CGContext
    ) {
        guard let pageRef = page.pageRef else { return }

        let displayedSize = displayedMediaBoxSize(for: page)
        let fittedRect = geometry.fittedRect(
            forSourcePageSize: displayedSize,
            pageIndex: pageIndex
        ).offsetBy(dx: 0, dy: -pageRect.minY)
        let localFittedRect = CGRect(origin: .zero, size: fittedRect.size)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = min(3, max(1, abs(ctx.ctm.a)))
        let renderer = UIGraphicsImageRenderer(size: fittedRect.size, format: format)
        let raster = renderer.image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(localFittedRect)

            let rasterContext = rendererContext.cgContext
            rasterContext.translateBy(x: 0, y: fittedRect.height)
            rasterContext.scaleBy(x: 1, y: -1)
            rasterContext.concatenate(
                pdfDrawingTransform(
                    for: pageRef,
                    displayedMediaBoxSize: displayedSize,
                    fittingInto: localFittedRect
                )
            )
            rasterContext.drawPDFPage(pageRef)
        }
        let renderedImage = interfaceStyle == .dark
            ? PdfRasterAppearance.invertedPreservingHue(raster)
            : raster

        ctx.saveGState()
        ctx.clip(to: pageBounds)
        UIGraphicsPushContext(ctx)
        renderedImage.draw(
            in: fittedRect,
            blendMode: interfaceStyle == .dark ? .screen : .multiply,
            alpha: 1
        )
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

    private static func pdfDrawingTransform(
        for pageRef: CGPDFPage,
        displayedMediaBoxSize: CGSize,
        fittingInto fittedRect: CGRect
    ) -> CGAffineTransform {
        let referenceRect = CGRect(origin: .zero, size: displayedMediaBoxSize)
        // Keep Core Graphics' media-box and rotation handling at native size,
        // then apply the magnification that getDrawingTransform omits.
        let nativeTransform = pageRef.getDrawingTransform(
            .mediaBox,
            rect: referenceRect,
            rotate: 0,
            preserveAspectRatio: true
        )
        let scale = min(
            fittedRect.width / referenceRect.width,
            fittedRect.height / referenceRect.height
        )
        let fittingTransform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: fittedRect.midX - referenceRect.midX * scale,
            ty: fittedRect.midY - referenceRect.midY * scale
        )
        return nativeTransform.concatenating(fittingTransform)
    }

    private static func displayedMediaBoxSize(for page: PDFPage) -> CGSize {
        let size = page.bounds(for: .mediaBox).size
        let rotation = ((page.rotation % 360) + 360) % 360
        guard rotation == 90 || rotation == 270 else { return size }
        return CGSize(width: size.height, height: size.width)
    }

    private static func drawInk(
        _ drawing: PKDrawing,
        pageRect: CGRect,
        pageBounds: CGRect,
        interfaceStyle: UIUserInterfaceStyle,
        in ctx: CGContext
    ) {
        var inkImage = UIImage()
        UITraitCollection(userInterfaceStyle: interfaceStyle).performAsCurrent {
            inkImage = drawing.image(from: pageRect, scale: 2)
        }

        UIGraphicsPushContext(ctx)
        inkImage.draw(in: pageBounds)
        UIGraphicsPopContext()
    }

    private static func drawImage(
        _ imageContent: ImageContent,
        for element: CanvasElement,
        pageRect: CGRect,
        pageBounds: CGRect,
        imagesByAssetPath: [String: UIImage],
        in ctx: CGContext
    ) {
        let absoluteFrame = cgRect(element.frame)
        guard element.drawnBoundingBox.intersects(pageRect),
              let image = imagesByAssetPath[imageContent.assetPath],
              image.size.width > 0,
              image.size.height > 0 else {
            return
        }

        let frame = absoluteFrame.offsetBy(dx: 0, dy: -pageRect.minY)
        let fitScale = min(
            frame.width / image.size.width,
            frame.height / image.size.height
        )
        let fittedSize = CGSize(
            width: image.size.width * fitScale,
            height: image.size.height * fitScale
        )
        let fittedRect = CGRect(
            x: -fittedSize.width / 2,
            y: -fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )

        ctx.saveGState()
        ctx.clip(to: pageBounds)
        ctx.translateBy(x: frame.midX, y: frame.midY)
        ctx.rotate(by: CGFloat(element.rotation))
        UIGraphicsPushContext(ctx)
        image.draw(in: fittedRect)
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

    private static func drawShape(
        _ shapeContent: ShapeContent,
        for element: CanvasElement,
        pageRect: CGRect,
        pageBounds: CGRect,
        interfaceStyle: UIUserInterfaceStyle,
        in ctx: CGContext
    ) {
        guard element.drawnBoundingBox.intersects(pageRect) else { return }

        let path = ShapeGeometry.path(
            for: shapeContent,
            in: element.frame,
            rotation: element.rotation
        )

        ctx.saveGState()
        ctx.clip(to: pageBounds)
        ctx.translateBy(x: 0, y: -pageRect.minY)
        ctx.addPath(path)
        ctx.setStrokeColor(
            ShapeInkAppearance.displayColor(
                for: shapeContent.strokeColor,
                style: interfaceStyle
            ).cgColor
        )
        ctx.setLineWidth(CGFloat(shapeContent.strokeWidth))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawText(
        _ textContent: TextBoxContent,
        for element: CanvasElement,
        pageRect: CGRect,
        pageBounds: CGRect,
        in ctx: CGContext
    ) {
        guard element.drawnBoundingBox.intersects(pageRect) else { return }

        let grownFrame = growTextFrame(element.frame, textContent: textContent)
        let color = UIColor(
            red: CGFloat(textContent.color.red),
            green: CGFloat(textContent.color.green),
            blue: CGFloat(textContent.color.blue),
            alpha: CGFloat(textContent.color.alpha)
        )
        let attributedString = NSAttributedString(
            string: textContent.text,
            attributes: [
                .font: newsreaderFont(size: CGFloat(textContent.fontSize)),
                .foregroundColor: color,
            ]
        )

        let frame = cgRect(grownFrame).offsetBy(dx: 0, dy: -pageRect.minY)
        let drawRect = CGRect(
            x: -frame.width / 2,
            y: -frame.height / 2,
            width: frame.width,
            height: frame.height
        ).insetBy(dx: 6, dy: 6)

        ctx.saveGState()
        ctx.clip(to: pageBounds)
        ctx.translateBy(x: frame.midX, y: frame.midY)
        ctx.rotate(by: CGFloat(element.rotation))
        UIGraphicsPushContext(ctx)
        attributedString.draw(in: drawRect)
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

    static func growTextFrame(
        _ frame: CanvasRect,
        textContent: TextBoxContent
    ) -> CanvasRect {
        let attributedString = NSAttributedString(
            string: textContent.text,
            attributes: [
                .font: newsreaderFont(size: CGFloat(textContent.fontSize)),
            ]
        )
        let insetWidth = max(CGFloat(frame.width) - 12, 0)
        let measured = attributedString.boundingRect(
            with: CGSize(width: insetWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let grownHeight = max(frame.height, Double(ceil(measured.height) + 12))
        return CanvasRect(
            x: frame.x,
            y: frame.y,
            width: frame.width,
            height: grownHeight
        )
    }

    private static func newsreaderFont(size: CGFloat) -> UIFont {
        let candidates = ["Newsreader", "Newsreader16pt-Regular", "Newsreader-Regular"]
        if let font = candidates.lazy.compactMap({ UIFont(name: $0, size: size) }).first {
            return font
        }

        let systemFont = UIFont.systemFont(ofSize: size, weight: .regular)
        guard let descriptor = systemFont.fontDescriptor.withDesign(.serif) else {
            return systemFont
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func cgRect(_ rect: CanvasRect) -> CGRect {
        CGRect(
            x: CGFloat(rect.x),
            y: CGFloat(rect.y),
            width: CGFloat(rect.width),
            height: CGFloat(rect.height)
        )
    }
}

extension CanvasElement {
    /// Rotated AABB of the element's effective frame: for text elements, the frame grown
    /// to the measured text height using top-anchored growth; otherwise the persisted frame.
    /// Non-text elements take a fast path without text measurement.
    var effectiveBoundingBox: CGRect {
        guard case .text(let textContent) = content else {
            return rotatedBoundingBox
        }

        var effectiveElement = self
        effectiveElement.frame = NotePageRenderer.growTextFrame(
            frame,
            textContent: textContent
        )
        return effectiveElement.rotatedBoundingBox
    }

    /// Bounds of everything a page render paints for this element. A shape's stroke straddles
    /// its path by half the stroke width, so its ink reaches outside `effectiveBoundingBox`:
    /// a thick shape whose frame stops at a page boundary still paints onto the next page.
    /// Culling or counting pages against the un-inflated box truncates that overhang, since
    /// every element is drawn clipped to the page it is drawn for.
    ///
    /// Half the stroke width is the exact outset: the renderer strokes with round caps and
    /// joins, so no corner overshoots the way a miter join would.
    var drawnBoundingBox: CGRect {
        guard case .shape(let shapeContent) = content else { return effectiveBoundingBox }

        let halfStrokeWidth = CGFloat(shapeContent.strokeWidth) / 2
        // Inflating the rotated box (rather than the frame) is what keeps this exact for
        // rotated shapes: outsetting by a disc commutes with the rotation.
        return rotatedBoundingBox
            .standardized
            .insetBy(dx: -halfStrokeWidth, dy: -halfStrokeWidth)
    }
}
