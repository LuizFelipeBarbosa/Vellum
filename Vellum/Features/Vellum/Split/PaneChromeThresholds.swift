import CoreGraphics

@MainActor
enum PaneChromeThresholds {
    static let backlinksRailMinWidth: CGFloat = 560
    static let suggestionsAndThumbnailsMinWidth: CGFloat = 480
    static let entityChipsMinWidth: CGFloat = 400
    // Below this the header's trailing cluster overflows the pane bounds.
    static let fullHeaderMinWidth: CGFloat = 420
}
