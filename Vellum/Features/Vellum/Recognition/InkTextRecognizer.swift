import PencilKit
import UIKit
import Vision
import VellumCore

actor InkTextRecognizer: InkTextRecognizing {
    func recognizeInk(
        drawingData: Data?,
        geometry: PageGeometry,
        bandCount: Int
    ) async throws -> [RecognizedLine] {
        guard let drawingData,
              let drawing = try? PKDrawing(data: drawingData),
              !drawing.strokes.isEmpty else {
            return []
        }

        var recognizedLines: [RecognizedLine] = []
        for band in Self.inkedBands(
            of: drawing,
            geometry: geometry,
            bandCount: bandCount
        ) {
            try Task.checkCancellation()

            let pageRect = geometry.pageRect(index: band)
            guard let image = Self.rasterize(
                drawing,
                pageRect: pageRect,
                scale: 2
            ) else {
                continue
            }
            recognizedLines.append(
                contentsOf: try await Self.recognizeLines(
                    in: image,
                    contentRect: pageRect,
                    scale: 2
                )
            )
        }
        return recognizedLines
    }

    nonisolated static func inkedBands(
        of drawing: PKDrawing,
        geometry: PageGeometry,
        bandCount: Int
    ) -> [Int] {
        guard bandCount > 0 else { return [] }

        return Set(drawing.strokes.map { stroke in
            PageBandAssignment.band(
                forAnchorY: stroke.renderBounds.midY,
                bandCount: bandCount,
                geometry: geometry
            )
        }).sorted()
    }

    nonisolated static func rasterize(
        _ drawing: PKDrawing,
        pageRect: CGRect,
        scale: CGFloat
    ) -> CGImage? {
        var inkImage = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            inkImage = drawing.image(from: pageRect, scale: scale)
        }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: pageRect.size, format: format)
        let localPageRect = CGRect(origin: .zero, size: pageRect.size)
        return renderer.image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(localPageRect)
            inkImage.draw(in: localPageRect)
        }.cgImage
    }

    nonisolated static func recognizeLines(
        in image: CGImage,
        contentRect: CGRect,
        scale: CGFloat
    ) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)

        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }

            let text = candidate.string
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let pixelRect = observation.boundingBox.toImageCoordinates(
                CGSize(width: image.width, height: image.height),
                origin: .upperLeft
            )
            return RecognizedLine(
                text: text,
                rect: CanvasRect(
                    x: Double(contentRect.origin.x + pixelRect.origin.x / scale),
                    y: Double(contentRect.origin.y + pixelRect.origin.y / scale),
                    width: Double(pixelRect.width / scale),
                    height: Double(pixelRect.height / scale)
                ),
                confidence: Double(candidate.confidence),
                source: .ink
            )
        }
    }
}
