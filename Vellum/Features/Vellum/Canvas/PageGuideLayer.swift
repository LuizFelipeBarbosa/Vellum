import SwiftUI
import VellumCore

/// Viewport-sized background that draws the visible portion of the paginated paper:
/// page background, 24-pt dot grid aligned to content space, dashed A4 page separators,
/// small page-number labels. Replaces the static VellumDotGrid.
struct PageGuideLayer: View {
    let viewport: CanvasViewport
    let viewportSize: CGSize
    let pageCount: Int

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(VellumTheme.paper)
            )

            let visibleRect = viewport.visibleContentRect(viewportSize: viewportSize)
            let firstVisible = PageLayout.pageIndex(
                forContentY: visibleRect.minY,
                pageCount: pageCount
            )
            let lastVisible = PageLayout.pageIndex(
                forContentY: visibleRect.maxY,
                pageCount: pageCount
            )

            for index in firstVisible...lastVisible {
                let contentPageRect = PageLayout.pageRect(index: index)
                let viewPageRect = viewport.viewRect(fromContent: contentPageRect)
                context.fill(Path(viewPageRect), with: .color(VellumTheme.card))

                let visiblePageRect = visibleRect.intersection(contentPageRect)
                guard !visiblePageRect.isNull, !visiblePageRect.isEmpty else { continue }

                let firstX = firstGridCoordinate(
                    atOrAfter: visiblePageRect.minX,
                    origin: contentPageRect.minX
                )
                let firstY = firstGridCoordinate(
                    atOrAfter: visiblePageRect.minY,
                    origin: contentPageRect.minY
                )
                let dotRadius = max(0.5, min(2, viewport.zoomScale))
                var dots = Path()

                for x in stride(from: firstX, through: visiblePageRect.maxX, by: 24) {
                    for y in stride(from: firstY, through: visiblePageRect.maxY, by: 24) {
                        let viewPoint = viewport.viewPoint(fromContent: CGPoint(x: x, y: y))
                        dots.addEllipse(
                            in: CGRect(
                                x: viewPoint.x - dotRadius,
                                y: viewPoint.y - dotRadius,
                                width: dotRadius * 2,
                                height: dotRadius * 2
                            )
                        )
                    }
                }

                var pageContext = context
                pageContext.clip(to: Path(viewPageRect))
                pageContext.fill(dots, with: .color(VellumTheme.ink(0.12)))
                pageContext.draw(
                    Text("\(index + 1)")
                        .font(.vellumMono(10))
                        .foregroundStyle(VellumTheme.ink(0.25)),
                    at: CGPoint(x: viewPageRect.maxX - 8, y: viewPageRect.minY + 8),
                    anchor: .topTrailing
                )
            }

            if firstVisible < lastVisible {
                for index in firstVisible..<lastVisible {
                    let contentPageRect = PageLayout.pageRect(index: index)
                    let start = viewport.viewPoint(
                        fromContent: CGPoint(
                            x: contentPageRect.minX,
                            y: contentPageRect.maxY
                        )
                    )
                    let end = viewport.viewPoint(
                        fromContent: CGPoint(
                            x: contentPageRect.maxX,
                            y: contentPageRect.maxY
                        )
                    )
                    var separator = Path()
                    separator.move(to: start)
                    separator.addLine(to: end)
                    context.stroke(
                        separator,
                        with: .color(VellumTheme.ink(0.18)),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                    )
                }
            }
        }
    }

    private func firstGridCoordinate(atOrAfter value: CGFloat, origin: CGFloat) -> CGFloat {
        origin + ((value - origin) / 24).rounded(.up) * 24
    }
}

struct PageTrackerBadge: View {
    let currentPage: Int
    let pageCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("\(currentPage) / \(pageCount)")
                .font(.vellumMono(11))
                .foregroundStyle(VellumTheme.mutedDark)
                .contentTransition(.numericText())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(VellumTheme.popover, in: Capsule())
        .overlay {
            Capsule()
                .stroke(VellumTheme.ink(0.12), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
    }
}

struct ZoomResetPill: View {
    let zoomPercentOfFit: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("\(zoomPercentOfFit)%")
                .font(.vellumMono(11))
                .foregroundStyle(VellumTheme.mutedDark)
                .contentTransition(.numericText())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(VellumTheme.popover, in: Capsule())
        .overlay {
            Capsule()
                .stroke(VellumTheme.ink(0.12), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
    }
}
