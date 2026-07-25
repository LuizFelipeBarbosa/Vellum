import PencilKit
import UIKit
import VellumCore

/// Mirrors PencilKit's dark-mode ink adaptation so a snapped shape matches
/// ink drawn with the same tool color. Stored CodableColor values are authored
/// against light-mode semantics; this only changes how they are DISPLAYED.
enum ShapeInkAppearance {
    static func displayColor(
        for color: CodableColor,
        style: UIUserInterfaceStyle
    ) -> UIColor {
        let stored = color.uiColor
        guard style == .dark else { return stored }
        let converted = PKInkingTool.convertColor(stored, from: .light, to: .dark)
        // convertColor may not preserve alpha faithfully (marker/highlighter shapes store
        // alpha 0.55) — re-apply the original alpha explicitly so translucency survives.
        return converted.withAlphaComponent(CGFloat(color.alpha))
    }
}
