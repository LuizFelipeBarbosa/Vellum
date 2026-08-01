import CoreGraphics
import Foundation
import PencilKit
import VellumCore

@MainActor
enum PageDeleter {
    struct Result {
        var drawing: PKDrawing
        var elements: [CanvasElement]
        var pages: [NotePage]
    }

    static func deletePage(
        at index: Int,
        drawing: PKDrawing,
        elements: [CanvasElement],
        pages: [NotePage],
        geometry: PageGeometry
    ) -> Result {
        let bandCount = pages.count
        guard bandCount > 1, pages.indices.contains(index) else {
            return Result(drawing: drawing, elements: elements, pages: pages)
        }

        let strokes = drawing.strokes.compactMap { stroke -> PKStroke? in
            // A boundary-straddling stroke follows the band containing its midpoint.
            let band = PageBandAssignment.band(
                forAnchorY: stroke.renderBounds.midY,
                bandCount: bandCount,
                geometry: geometry
            )
            guard band != index else { return nil }
            guard band > index else { return stroke }

            return StrokeEditing.copy(
                stroke,
                translatedBy: CGSize(width: 0, height: -geometry.pageHeight)
            )
        }

        let remainingElements = elements.compactMap { element -> CanvasElement? in
            let band = PageBandAssignment.band(
                forAnchorY: element.effectiveBoundingBox.midY,
                bandCount: bandCount,
                geometry: geometry
            )
            guard band != index else { return nil }
            guard band > index else { return element }

            var moved = element
            moved.frame.y -= Double(geometry.pageHeight)
            return moved
        }

        var remainingPages = pages
        remainingPages.remove(at: index)
        for pageIndex in remainingPages.indices {
            remainingPages[pageIndex].order = pageIndex
        }

        if index == 0 {
            let attachment = pages[0]
            remainingPages[0].drawingAssetPath = attachment.drawingAssetPath
            remainingPages[0].plainText = attachment.plainText
            remainingPages[0].elements = remainingElements
        }

        return Result(
            drawing: PKDrawing(strokes: strokes),
            elements: remainingElements,
            pages: remainingPages
        )
    }
}
