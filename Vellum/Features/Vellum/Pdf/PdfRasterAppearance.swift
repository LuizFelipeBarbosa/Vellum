import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum PdfRasterAppearance {
    private static let context = CIContext()

    static func invertedPreservingHue(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let inputImage = CIImage(cgImage: cgImage)
        let invertFilter = CIFilter.colorInvert()
        invertFilter.inputImage = inputImage
        guard let invertedImage = invertFilter.outputImage else { return image }

        let hueFilter = CIFilter.hueAdjust()
        hueFilter.inputImage = invertedImage
        hueFilter.angle = .pi
        guard let outputImage = hueFilter.outputImage,
              let outputCGImage = context.createCGImage(
                  outputImage,
                  from: inputImage.extent
              ) else {
            return image
        }

        return UIImage(
            cgImage: outputCGImage,
            scale: image.scale,
            orientation: image.imageOrientation
        )
    }
}
