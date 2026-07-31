import CoreGraphics

@MainActor
struct PaneContext: @MainActor Equatable {
    let pane: NotePane
    let isFocused: Bool
    let fitsBacklinksRail: Bool
    let fitsSuggestionsAndThumbnails: Bool
    let fitsEntityChips: Bool
    let hasCompactHeader: Bool
    let isSplit: Bool
    let canvasGeneration: Int

    // Resolve thresholds here so pane values stay equal through a divider drag.
    init(
        pane: NotePane,
        isFocused: Bool,
        paneSize: CGSize,
        paneCount: Int,
        canvasGeneration: Int
    ) {
        self.pane = pane
        self.isFocused = isFocused
        fitsBacklinksRail = paneSize.width >= PaneChromeThresholds.backlinksRailMinWidth
            && paneSize.height >= PaneChromeThresholds.backlinksRailMinHeight
        fitsSuggestionsAndThumbnails =
            paneSize.width >= PaneChromeThresholds.suggestionsAndThumbnailsMinWidth
            && paneSize.height >= PaneChromeThresholds.suggestionsAndThumbnailsMinHeight
        fitsEntityChips = paneSize.width >= PaneChromeThresholds.entityChipsMinWidth
        hasCompactHeader = paneSize.width < PaneChromeThresholds.fullHeaderMinWidth
        isSplit = paneCount > 1
        self.canvasGeneration = canvasGeneration
    }

    static func == (lhs: PaneContext, rhs: PaneContext) -> Bool {
        lhs.pane === rhs.pane
            && lhs.isFocused == rhs.isFocused
            && lhs.fitsBacklinksRail == rhs.fitsBacklinksRail
            && lhs.fitsSuggestionsAndThumbnails == rhs.fitsSuggestionsAndThumbnails
            && lhs.fitsEntityChips == rhs.fitsEntityChips
            && lhs.hasCompactHeader == rhs.hasCompactHeader
            && lhs.isSplit == rhs.isSplit
            && lhs.canvasGeneration == rhs.canvasGeneration
    }
}
