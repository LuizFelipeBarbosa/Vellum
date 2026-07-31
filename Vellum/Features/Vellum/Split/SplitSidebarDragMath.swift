import CoreGraphics

struct SplitSidebarDragMath: Sendable {
    static let rowHeight: CGFloat = 56

    static func rowIndex(
        forContentY y: CGFloat,
        rowHeight: CGFloat = SplitSidebarDragMath.rowHeight,
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
