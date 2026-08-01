import CoreGraphics
import Foundation
import PencilKit
import VellumCore

@MainActor
enum PageReorderer {
    struct Result {
        var drawing: PKDrawing
        var elements: [CanvasElement]
        var pages: [NotePage]
    }

    static func movePages(
        source: IndexSet,
        to destination: Int,
        drawing: PKDrawing,
        elements: [CanvasElement],
        pages: [NotePage],
        geometry: PageGeometry
    ) -> Result {
        let bandCount = pages.count
        guard bandCount > 0 else {
            return Result(drawing: drawing, elements: elements, pages: pages)
        }

        let permutation = PageBandAssignment.permutation(
            count: bandCount,
            moving: source,
            to: destination
        )
        guard permutation != Array(0..<bandCount) else {
            return Result(drawing: drawing, elements: elements, pages: pages)
        }

        let strokes = drawing.strokes.map { stroke in
            // A boundary-straddling stroke moves whole with the band containing its midpoint.
            let band = PageBandAssignment.band(
                forAnchorY: stroke.renderBounds.midY,
                bandCount: bandCount,
                geometry: geometry
            )
            let newBand = permutation[band]
            guard newBand != band else { return stroke }

            let delta = CGFloat(newBand - band) * geometry.pageHeight
            return StrokeEditing.copy(stroke, translatedBy: CGSize(width: 0, height: delta))
        }

        let reorderedElements = elements.map { element in
            let band = PageBandAssignment.band(
                forAnchorY: element.effectiveBoundingBox.midY,
                bandCount: bandCount,
                geometry: geometry
            )
            let newBand = permutation[band]
            guard newBand != band else { return element }

            var moved = element
            moved.frame.y += Double(CGFloat(newBand - band) * geometry.pageHeight)
            return moved
        }

        var reorderedPages = pages
        for oldIndex in pages.indices {
            let newIndex = permutation[oldIndex]
            var page = pages[oldIndex]
            page.order = newIndex
            reorderedPages[newIndex] = page
        }

        if permutation[0] != 0 {
            let attachment = pages[0]

            var firstPage = reorderedPages[0]
            firstPage.drawingAssetPath = attachment.drawingAssetPath
            firstPage.plainText = attachment.plainText
            firstPage.elements = attachment.elements
            reorderedPages[0] = firstPage

            var pageThatLostAttachment = reorderedPages[permutation[0]]
            pageThatLostAttachment.drawingAssetPath =
                "pages/\(pageThatLostAttachment.id.uuidString)/drawing.data"
            pageThatLostAttachment.plainText = ""
            pageThatLostAttachment.elements = []
            reorderedPages[permutation[0]] = pageThatLostAttachment
        }

        return Result(
            drawing: PKDrawing(strokes: strokes),
            elements: reorderedElements,
            pages: reorderedPages
        )
    }
}
