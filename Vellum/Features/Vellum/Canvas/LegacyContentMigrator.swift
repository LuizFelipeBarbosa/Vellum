import PencilKit
import VellumCore

enum LegacyContentMigrator {
    struct Result {
        var drawing: PKDrawing
        var elements: [CanvasElement]
        var didMigrate: Bool
    }

    /// For legacy layout versions, scales content uniformly about the origin so its max X
    /// fits PageLayout.contentWidth. Current layout versions are always returned unchanged.
    static func migrateIfNeeded(
        drawing: PKDrawing,
        elements: [CanvasElement],
        layoutVersion: Int
    ) -> Result {
        guard layoutVersion < Note.currentLayoutVersion else {
            return Result(drawing: drawing, elements: elements, didMigrate: false)
        }

        let drawingMaxX = drawing.bounds.isNull ? 0 : drawing.bounds.maxX
        let contentMaxX = elements.reduce(drawingMaxX) { maximum, element in
            max(maximum, element.rotatedBoundingBox.maxX)
        }

        guard contentMaxX > PageLayout.contentWidth else {
            return Result(drawing: drawing, elements: elements, didMigrate: false)
        }

        let factor = PageLayout.contentWidth / contentMaxX
        let scaledDrawing = drawing.transformed(
            using: CGAffineTransform(scaleX: factor, y: factor)
        )
        let scaledElements = elements.map { element in
            var scaledElement = element
            let elementFactor = Double(factor)
            scaledElement.frame.x *= elementFactor
            scaledElement.frame.y *= elementFactor
            scaledElement.frame.width *= elementFactor
            scaledElement.frame.height *= elementFactor

            if case .text(var text) = scaledElement.content {
                text.fontSize *= elementFactor
                scaledElement.content = .text(text)
            }

            return scaledElement
        }

        return Result(
            drawing: scaledDrawing,
            elements: scaledElements,
            didMigrate: true
        )
    }
}
