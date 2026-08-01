import Foundation
import PencilKit
import UIKit
import VellumCore

/// The canvas primitives the selection, transform, hit-testing, and page tests build on.
///
/// Every fixture here is inert: the strokes carry a flat pen profile and the elements point at
/// asset paths nothing reads, so a test only has to state the geometry it actually asserts on.
enum CanvasFixtures {
    /// A pen stroke sampled at `locations`, one control point per location, 0.1 s apart.
    ///
    /// The pressure profile is deliberately flat -- full force, zero azimuth, pen held upright
    /// -- so a stroke's rendered extent follows only from `locations` and `size`.
    static func makeStroke(
        locations: [CGPoint],
        color: UIColor = .black,
        size: CGSize = CGSize(width: 4, height: 4),
        transform: CGAffineTransform = .identity,
        creationDate: Date = Date()
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
            ink: PKInk(.pen, color: color),
            path: PKStrokePath(controlPoints: points, creationDate: creationDate),
            transform: transform
        )
    }

    /// The straight two-point form. Identical to `makeStroke(locations: [start, end])`.
    static func makeStroke(from start: CGPoint, to end: CGPoint) -> PKStroke {
        makeStroke(locations: [start, end])
    }

    /// A text element occupying `frame`.
    ///
    /// No test asserts on the text itself -- callers override it only to say what the element
    /// stands for. `layerPlacement` defaults to nil, which is *not* the same as `.aboveInk`:
    /// nil is left out of the encoded form and resolved from the content kind on read.
    static func makeTextElement(
        frame: CanvasRect,
        text: String = "Selected",
        rotation: Double = 0,
        layerPlacement: LayerPlacement? = nil
    ) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: text,
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame,
            rotation: rotation,
            layerPlacement: layerPlacement
        )
    }

    /// An image element occupying `frame`. The asset path is a placeholder -- these tests
    /// exercise element bookkeeping, never the image bytes.
    static func makeImageElement(
        frame: CanvasRect,
        rotation: Double = 0
    ) -> CanvasElement {
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: "assets/image.jpg",
                    originalPixelSize: CanvasSize(width: 100, height: 100)
                )
            ),
            frame: frame,
            rotation: rotation
        )
    }
}
