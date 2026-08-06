import CoreGraphics
import Foundation

/// Seam the app target implements with Vision (`VNRecognizeTextRequest`). This package
/// stays platform-free; the Vision-backed conformer lives in the app target.
public protocol InkTextRecognizing: Sendable {
    /// Recognized lines with rects already transformed into content space (the same
    /// space as `CanvasElement.frame`). Returns `[]` when `drawingData` is `nil` or
    /// represents an empty drawing.
    func recognizeInk(
        drawingData: Data?,
        geometry: PageGeometry,
        bandCount: Int
    ) async throws -> [RecognizedLine]
}
