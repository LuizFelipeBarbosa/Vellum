import CoreGraphics

/// Index math shared by the vertical drag-to-reorder lists: the page-thumbnail panel and the
/// split-view note sidebar.
enum RowDragMath {
    /// The row containing `y` in scroll-content space, or nil when the point falls outside the
    /// list. Non-finite input is refused before the `Int(_:)` conversion, which traps on infinity.
    static func rowIndex(
        forContentY y: CGFloat,
        rowHeight: CGFloat,
        rowCount: Int
    ) -> Int? {
        guard y.isFinite,
              y >= 0,
              rowHeight.isFinite,
              rowHeight > 0,
              rowCount > 0 else {
            return nil
        }

        let index = Int(y / rowHeight)
        return index < rowCount ? index : nil
    }
}
