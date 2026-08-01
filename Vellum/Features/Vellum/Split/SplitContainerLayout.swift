import Foundation
import SwiftUI
import VellumCore

/// How far a committed pane has to move and scale to sit where the drag
/// preview says it will land.
struct PanePreviewTransform {
    let scale: CGSize
    let offset: CGSize

    static let identity = PanePreviewTransform(
        scale: CGSize(width: 1, height: 1),
        offset: .zero
    )
}

/// The placeholder drawn under a lifted note: where it would land, and whether
/// landing there is a split, a focus change, or a refusal.
struct PaneGhostConfiguration {
    let title: String
    let spaceColor: Color?
    let intent: PaneGhostIntent
    let frame: CGRect
}

/// Pure geometry for the split container. Every value here is a function of its
/// arguments alone, so it can be solved by the type checker — and read — without
/// the surrounding view hierarchy.
enum SplitContainerLayout {
    static let sidebarWidth: CGFloat = 300
    static let sidebarOuterPadding: CGFloat = 18

    /// Everything left of this x is sidebar: a drag that ends here cancels
    /// rather than dropping into the leftmost pane hiding underneath.
    static let sidebarCancelZoneMaxX: CGFloat =
        sidebarOuterPadding + sidebarWidth + sidebarOuterPadding

    /// The seam between column `dividerIndex` and the one after it.
    static func columnDividerX(
        columnWidths: [CGFloat],
        dividerIndex: Int
    ) -> CGFloat {
        columnWidths.prefix(dividerIndex + 1).reduce(0, +)
    }

    /// The seam between row `dividerIndex` and the one after it, centred in its
    /// own column.
    static func rowDividerCenter(
        columnWidths: [CGFloat],
        rowHeights: [[CGFloat]],
        columnIndex: Int,
        dividerIndex: Int
    ) -> CGPoint {
        let leadingWidth: CGFloat = columnWidths.prefix(columnIndex).reduce(0, +)
        let stackedHeight: CGFloat = rowHeights[columnIndex]
            .prefix(dividerIndex + 1)
            .reduce(0, +)
        return CGPoint(
            x: leadingWidth + columnWidths[columnIndex] / 2,
            y: stackedHeight
        )
    }

    static func panePreviewTransform(
        at index: PaneIndex,
        target: SplitGridDropTarget?,
        committedGrid: SplitGridSnapshot,
        previewGrid: SplitGridSnapshot,
        containerSize: CGSize
    ) -> PanePreviewTransform {
        guard let target,
              let committedFrame = SplitGridPolicy.paneFrame(
                at: index,
                grid: committedGrid,
                containerSize: containerSize
              ),
              let previewFrame = SplitGridPolicy.paneFrame(
                at: SplitGridPolicy.paneIndexAfterInserting(target, index),
                grid: previewGrid,
                containerSize: containerSize
              ),
              committedFrame.width > 0,
              committedFrame.height > 0 else {
            return .identity
        }

        return PanePreviewTransform(
            scale: CGSize(
                width: previewFrame.width / committedFrame.width,
                height: previewFrame.height / committedFrame.height
            ),
            offset: CGSize(
                width: previewFrame.minX - committedFrame.minX,
                height: previewFrame.minY - committedFrame.minY
            )
        )
    }

    static func paneGhostConfiguration(
        lift: SplitDragLift?,
        resolution: SidebarDropResolution?,
        refusedTarget: SplitGridDropTarget?,
        committedGrid: SplitGridSnapshot,
        previewGrid: SplitGridSnapshot,
        containerSize: CGSize
    ) -> PaneGhostConfiguration? {
        guard let lift else { return nil }

        let frame: CGRect
        let intent: PaneGhostIntent
        switch resolution {
        case .target(.existingPane(let index)):
            guard let existingFrame = SplitGridPolicy.paneFrame(
                at: index,
                grid: committedGrid,
                containerSize: containerSize
            ) else {
                return nil
            }
            frame = existingFrame
            intent = .alreadyOpen

        case .target(let target):
            guard let insertedIndex = SplitGridPolicy.insertedPaneIndex(for: target),
                  let insertedFrame = SplitGridPolicy.paneFrame(
                    at: insertedIndex,
                    grid: previewGrid,
                    containerSize: containerSize
                  ) else {
                return nil
            }
            frame = insertedFrame
            intent = .split

        case .capacityFull:
            // A refusal leaves the panes untransformed, so the ghost has to be
            // framed on the committed grid: the refused insertion's own index
            // belongs to a hypothetical grid this layout never adopts.
            guard let refusedTarget,
                  let refusedIndex = SplitGridPolicy.clampedPaneIndex(
                    for: refusedTarget,
                    in: committedGrid
                  ),
                  let refusedFrame = SplitGridPolicy.paneFrame(
                    at: refusedIndex,
                    grid: committedGrid,
                    containerSize: containerSize
                  ) else {
                return nil
            }
            frame = refusedFrame
            intent = .refused

        case .cancelZone, nil:
            return nil
        }

        return PaneGhostConfiguration(
            title: lift.title,
            spaceColor: lift.spaceColor,
            intent: intent,
            frame: frame
        )
    }

    static func sidebarToggleCenter(
        for frames: PaneHeaderFrames?,
        containerGlobalOrigin: CGPoint,
        isSidebarShowing: Bool
    ) -> CGPoint {
        let buttonRadius: CGFloat = 22
        let gap: CGFloat = 12
        let fallbackFrame = CGRect(x: 20, y: 10, width: 0, height: 44)
        let leftClusterFrame = if let frames,
                                  frames.leftClusterFrame != .zero {
            frames.leftClusterFrame.offsetBy(
                dx: -containerGlobalOrigin.x,
                dy: -containerGlobalOrigin.y
            )
        } else {
            fallbackFrame
        }
        let topOverlayFrame = if let frames,
                                 frames.topOverlayGlobalFrame != .zero {
            frames.topOverlayGlobalFrame.offsetBy(
                dx: -containerGlobalOrigin.x,
                dy: -containerGlobalOrigin.y
            )
        } else {
            fallbackFrame
        }
        let centerX = isSidebarShowing
            ? sidebarCancelZoneMaxX + buttonRadius
            : leftClusterFrame.minX + buttonRadius

        return CGPoint(
            x: centerX,
            y: topOverlayFrame.maxY + gap + buttonRadius
        )
    }

    static func topDockObstructions(
        for frames: PaneHeaderFrames?,
        containerGlobalOrigin: CGPoint
    ) -> TopDockObstructions? {
        guard let frames,
              frames.leftClusterFrame != .zero,
              frames.rightClusterFrame != .zero else {
            return nil
        }
        return TopDockObstructions(
            navbarTop: frames.leftClusterFrame.minY - containerGlobalOrigin.y,
            overlayBottom: frames.topOverlayGlobalFrame.maxY - containerGlobalOrigin.y,
            gapMinX: frames.leftClusterFrame.maxX - containerGlobalOrigin.x,
            gapMaxX: frames.rightClusterFrame.minX - containerGlobalOrigin.x
        )
    }
}

/// Formatters for the `vellum-split-state` accessibility value. Flow tests parse
/// these fields verbatim; the encodings are a test contract, not a display
/// detail, so none of them may change shape.
enum SplitStateReadout {
    static func grid(_ grid: SplitGridSnapshot) -> String {
        let encoded = grid.columns.map { column in
            let width = fraction(column.widthFraction)
            let rows = column.rowFractions
                .map { fraction($0) }
                .joined(separator: ",")
            return "\(width)[\(rows)]"
        }
        .joined(separator: "|")
        return encoded.isEmpty ? "none" : encoded
    }

    static func paneIndex(_ index: PaneIndex?) -> String {
        guard let index else { return "-1" }
        return "\(index.column).\(index.row)"
    }

    static func dragTarget(_ resolution: SidebarDropResolution?) -> String {
        switch resolution {
        case .cancelZone:
            "none"
        case .capacityFull:
            "none-capacity"
        case .target(.insertColumn(let index)):
            "col-\(index)"
        case .target(.insertRow(let column, let row)):
            "row-\(column).\(row)"
        case .target(.existingPane(let paneIndex)):
            "focus-\(paneIndex.column).\(paneIndex.row)"
        case nil:
            "none"
        }
    }

    private static func fraction(_ fraction: CGFloat) -> String {
        String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(fraction)
        )
    }
}
