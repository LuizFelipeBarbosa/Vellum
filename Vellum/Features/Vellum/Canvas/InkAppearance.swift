import PencilKit
import SwiftUI
import UIKit
import VellumCore

/// Mirrors PencilKit's dark-mode ink adaptation across displayed ink colors. Stored
/// CodableColor values are authored against light-mode semantics; this only changes
/// how they are DISPLAYED.
/// Probes established that PKInkingTool.init stores its UIColor literally, without
/// construction-time trait normalization.
/// Both PKCanvasView and PKDrawing.image(from:scale:) treat stored ink as
/// light-canonical and adapt it to current render-time traits inside PencilKit.
/// PencilCanvasView.swift sets PKCanvasView.overrideUserInterfaceStyle; converting
/// PKInkingTool/PKInk inputs double-converts and was therefore reverted.
/// InkAppearance is only for shape/text elements, toolbar color swatches and text-size
/// preview, PDF/PNG exports, and page thumbnails rendered through
/// SwiftUI/CoreGraphics/UIKit.
enum InkAppearance {
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

    static func style(
        colorScheme: ColorScheme,
        paperTint: CodableColor?
    ) -> UIUserInterfaceStyle {
        if let paperTint {
            return PageBackgroundStyle.isDarkTint(paperTint) ? .dark : .light
        }
        return colorScheme == .dark ? .dark : .light
    }

    static func storedColor(
        for displayed: UIColor,
        style: UIUserInterfaceStyle
    ) -> CodableColor {
        guard style == .dark else { return CodableColor(displayed) }
        let converted = PKInkingTool.convertColor(displayed, from: .dark, to: .light)
        return CodableColor(converted.withAlphaComponent(displayed.cgColor.alpha))
    }
}

extension EnvironmentValues {
    @Entry var inkDisplayStyle: UIUserInterfaceStyle = .light
}
