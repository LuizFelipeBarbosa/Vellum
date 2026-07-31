import CoreGraphics

@MainActor
enum PaneChromeThresholds {
    static let backlinksRailMinWidth: CGFloat = 560
    // Below this the backlinks rail does not have enough room in a stacked pane.
    static let backlinksRailMinHeight: CGFloat = 500
    static let suggestionsAndThumbnailsMinWidth: CGFloat = 480
    // Below this the suggestions and thumbnails overlays do not have enough room in a stacked pane.
    static let suggestionsAndThumbnailsMinHeight: CGFloat = 460
    static let entityChipsMinWidth: CGFloat = 400
    // Below this the header's trailing cluster overflows the pane bounds.
    static let fullHeaderMinWidth: CGFloat = 420
}
