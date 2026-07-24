import CoreGraphics

struct ThumbnailDragMath {
    static func proposedIndex(
        fingerPanelY: CGFloat,
        contentOffsetY: CGFloat,
        grabOffsetY: CGFloat,
        rowHeight: CGFloat,
        pageCount: Int
    ) -> Int {
        guard rowHeight > 0, pageCount > 0 else { return 0 }

        let rawIndex = Int(round(
            (fingerPanelY + contentOffsetY - grabOffsetY) / rowHeight
        ))
        return min(max(rawIndex, 0), pageCount - 1)
    }

    static func displacement(
        forRow index: Int,
        draggedIndex: Int,
        proposedIndex: Int,
        rowHeight: CGFloat
    ) -> CGFloat {
        if draggedIndex < proposedIndex,
           (draggedIndex + 1...proposedIndex).contains(index) {
            return -rowHeight
        }

        if draggedIndex > proposedIndex,
           (proposedIndex..<draggedIndex).contains(index) {
            return rowHeight
        }

        return 0
    }

    static func dropDestination(
        draggedIndex: Int,
        proposedIndex: Int
    ) -> Int {
        proposedIndex > draggedIndex ? proposedIndex + 1 : proposedIndex
    }

    static func grabOffsetY(
        fingerPanelY: CGFloat,
        contentOffsetY: CGFloat,
        draggedIndex: Int,
        rowHeight: CGFloat
    ) -> CGFloat {
        fingerPanelY + contentOffsetY - CGFloat(draggedIndex) * rowHeight
    }

    static func liftedIndex(
        fingerContentY: CGFloat,
        rowHeight: CGFloat,
        pageCount: Int
    ) -> Int? {
        guard fingerContentY >= 0, rowHeight > 0, pageCount > 0 else {
            return nil
        }

        let index = Int(fingerContentY / rowHeight)
        return index < pageCount ? index : nil
    }

    static func dragStartIndex(
        fingerContentX: CGFloat,
        fingerContentY: CGFloat,
        rowWidth: CGFloat,
        rowHeight: CGFloat,
        badgeZone: CGFloat,
        pageCount: Int
    ) -> Int? {
        guard let rowIndex = liftedIndex(
            fingerContentY: fingerContentY,
            rowHeight: rowHeight,
            pageCount: pageCount
        ) else {
            return nil
        }

        let rowY = fingerContentY - CGFloat(rowIndex) * rowHeight
        if fingerContentX > rowWidth - badgeZone,
           rowY < badgeZone {
            return nil
        }

        return rowIndex
    }
}
