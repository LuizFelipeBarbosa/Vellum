import Foundation
import ImageIO
import UIKit

enum ImageImportPipeline {
    struct ProcessedImage: Sendable {
        let jpegData: Data
        let pixelSize: CGSize
    }

    enum ImageImportError: Error {
        case undecodable
    }

    /// Decode, downscale to a max long edge, re-encode as JPEG. Runs off-main.
    /// Data-in/Data-out so nothing non-Sendable crosses the boundary.
    static func processForStorage(
        _ data: Data,
        maxDimension: CGFloat = 2048,
        compressionQuality: CGFloat = 0.8
    ) async throws -> ProcessedImage {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw ImageImportError.undecodable
            }

            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
            let sourceWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue
            let sourceHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
            let sourceLongEdge = max(sourceWidth ?? maxDimension, sourceHeight ?? maxDimension)
            let thumbnailMaxDimension = max(1, min(Double(maxDimension), sourceLongEdge))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxDimension
            ]

            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ),
            let jpegData = UIImage(cgImage: image).jpegData(
                compressionQuality: min(max(compressionQuality, 0), 1)
            ) else {
                throw ImageImportError.undecodable
            }

            return ProcessedImage(
                jpegData: jpegData,
                pixelSize: CGSize(width: image.width, height: image.height)
            )
        }.value
    }
}
