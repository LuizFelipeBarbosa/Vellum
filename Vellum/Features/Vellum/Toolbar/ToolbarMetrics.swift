import CoreGraphics

/// Shared layout metrics for the note toolbar (NoteToolbarView, ToolModeRow,
/// FavoriteColorRow). Later steps move those views onto these constants.
enum ToolbarMetrics {
    // Items
    static let itemHitSize: CGFloat = 40
    static let itemSpacing: CGFloat = 8
    static let captionSpacing: CGFloat = 2
    static let captionedItemMinWidth: CGFloat = 44
    static let selectedPillRadius: CGFloat = 8
    static let quietIconFrame: CGFloat = 32
    static let quietPadding: CGFloat = 4
    // Section paddings: along the item axis at section ends / across the item axis
    static let endPadding: CGFloat = 18
    static let crossPadding: CGFloat = 8
    // Collapsed pill
    static let collapsedSpacing: CGFloat = 8
    static let collapsedEndPadding: CGFloat = 14
    /// Extra along-axis inset for the collapse/expand button, which sits at the
    /// toolbar's corner-most position: the floating chrome's organic corners
    /// sweep ~half the cross extent (~29pt on the 56pt vertical bar), so the
    /// button's pill must clear that whole curved zone — `endPadding` alone
    /// leaves it clipped. 20pt puts the pill's corner-side edge past the curve.
    static let collapseCornerClearance: CGFloat = 20
    // Dividers
    static let dividerLength: CGFloat = 24
    static let dividerThickness: CGFloat = 1
    // Favorites strip
    static let favoritesStripCap: CGFloat = 292
    static let favoritesStripMin: CGFloat = 120
    static let favoritesDotSpacing: CGFloat = 12
    static let favoritesInnerPadding: CGFloat = 4

    /// Vertical tools column extent: 10 items + 2 dividers + 11 gaps + end
    /// paddings + the collapse button's corner clearance.
    static var verticalToolsExtent: CGFloat {
        10 * itemHitSize + 2 * dividerThickness + 11 * itemSpacing + 2 * endPadding
            + collapseCornerClearance
    }
    /// Favorites column chrome excluding the scrollable strip: add button (24)
    /// + rule (1) + stroke swatch (24) + 3 gaps + strip inner padding + end paddings.
    static var favoritesColumnChrome: CGFloat {
        24 + dividerThickness + 24 + 3 * itemSpacing + 2 * favoritesInnerPadding + 2 * endPadding
    }
    /// Replaces FavoriteColorRow.verticalChromeAllowance (was a hand-tuned 580).
    static var verticalNonStripAllowance: CGFloat {
        verticalToolsExtent + favoritesColumnChrome
    }
}

/// Clearance below the note's floating top overlay (header chips) for canvas
/// content and floating overlays. Must clear the split-view sidebar toggle,
/// which occupies topOverlayFrame.maxY+12 ... maxY+56 (12pt gap + 44pt button,
/// see SplitContainerLayout.sidebarToggleCenter), plus 8pt breathing room.
enum VellumOverlayMetrics {
    static let belowTopOverlayInset: CGFloat = 64
}
