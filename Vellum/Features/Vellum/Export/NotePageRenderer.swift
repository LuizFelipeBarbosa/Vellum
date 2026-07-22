import PencilKit
import SwiftUI
import UIKit
import VellumCore

@MainActor
enum NotePageRenderer {
    struct Content {
        var drawing: PKDrawing
        var elements: [CanvasElement]
        var imagesByAssetPath: [String: UIImage]
        var pageCount: Int
    }

    /// Draws page `pageIndex` into `ctx`, whose coordinate space is content points
    /// with the origin at the page's top-left.
    static func draw(pageIndex: Int, content: Content, in ctx: CGContext) {
        let pageRect = PageLayout.pageRect(index: pageIndex)
        let pageBounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: PageLayout.contentWidth,
                height: PageLayout.pageHeight
            )
        )

        ctx.saveGState()
        defer { ctx.restoreGState() }

        drawPaper(pageRect: pageRect, pageBounds: pageBounds, in: ctx)

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

        drawInk(content.drawing, pageRect: pageRect, pageBounds: pageBounds, in: ctx)

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

    /// Convenience rendering for one page at an A4-aspect point size and scale.
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
            let pointScale = pointSize.width / PageLayout.contentWidth
            rendererContext.cgContext.scaleBy(x: pointScale, y: pointScale)
            draw(pageIndex: pageIndex, content: content, in: rendererContext.cgContext)
        }
    }

    private static func drawPaper(
        pageRect: CGRect,
        pageBounds: CGRect,
        in ctx: CGContext
    ) {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let paperColor = UIColor(VellumTheme.card).resolvedColor(with: traits)
        let dotColor = UIColor(VellumTheme.ink)
            .resolvedColor(with: traits)
            .withAlphaComponent(0.12)

        ctx.setFillColor(paperColor.cgColor)
        ctx.fill(pageBounds)

        let spacing: CGFloat = 24
        let radius: CGFloat = 1
        let firstAbsoluteY = ceil(pageRect.minY / spacing) * spacing
        let path = CGMutablePath()
        var x: CGFloat = 0
        while x <= pageBounds.maxX {
            var y = firstAbsoluteY - pageRect.minY
            while y <= pageBounds.maxY {
                path.addEllipse(
                    in: CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
                y += spacing
            }
            x += spacing
        }

        ctx.setFillColor(dotColor.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private static func drawInk(
        _ drawing: PKDrawing,
        pageRect: CGRect,
        pageBounds: CGRect,
        in ctx: CGContext
    ) {
        var inkImage = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
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
        guard element.rotatedBoundingBox.intersects(pageRect),
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

    private static func drawText(
        _ textContent: TextBoxContent,
        for element: CanvasElement,
        pageRect: CGRect,
        pageBounds: CGRect,
        in ctx: CGContext
    ) {
        guard element.effectiveBoundingBox.intersects(pageRect) else { return }

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
    @MainActor
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
}
