import SwiftUI
import VellumCore

/// Viewport-sized background that draws the visible portion of the paginated paper:
/// page background, page-aligned pattern, dashed page separators,
/// small page-number labels. Replaces the static VellumDotGrid.
struct PageGuideLayer: View {
    enum Mode {
        case background
        case pdfAdornments
    }

    @Environment(\.displayScale) private var displayScale

    let viewport: CanvasViewport
    let viewportSize: CGSize
    let pageCount: Int
    let geometry: PageGeometry
    let style: PageBackgroundStyle
    var pdfBands: Set<Int> = []
    var mode: Mode = .background

    var body: some View {
        Canvas { context, size in
            if case .background = mode {
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(VellumTheme.paper)
                )
            }

            let visibleRect = viewport.visibleContentRect(viewportSize: viewportSize)
            let firstVisible = geometry.pageIndex(
                forContentY: visibleRect.minY,
                pageCount: pageCount
            )
            let lastVisible = geometry.pageIndex(
                forContentY: visibleRect.maxY,
                pageCount: pageCount
            )

            for index in firstVisible...lastVisible {
                let contentPageRect = geometry.pageRect(index: index)
                let viewPageRect = viewport.viewRect(fromContent: contentPageRect)
                if case .pdfAdornments = mode {
                    guard pdfBands.contains(index) else { continue }
                    context.draw(
                        Text("\(index + 1)")
                            .font(.vellumMono(10))
                            .foregroundStyle(VellumTheme.ink(0.25)),
                        at: CGPoint(x: viewPageRect.maxX - 8, y: viewPageRect.minY + 8),
                        anchor: .topTrailing
                    )
                    context.stroke(
                        Path(viewPageRect),
                        with: .color(VellumTheme.ink(0.18)),
                        lineWidth: 1
                    )
                    continue
                }

                let backingRect = viewPageRect
                    .offsetBy(dx: 0, dy: 2)
                    .insetBy(dx: -1, dy: -1)
                context.fill(
                    Path(backingRect),
                    with: .color(VellumTheme.ink(0.05))
                )
                if let tint = style.paperTint {
                    context.fill(
                        Path(viewPageRect),
                        with: .color(
                            Color(red: tint.red, green: tint.green, blue: tint.blue)
                                .opacity(tint.alpha)
                        )
                    )
                } else {
                    context.fill(Path(viewPageRect), with: .color(VellumTheme.card))
                }

                let visiblePageRect = visibleRect.intersection(contentPageRect)
                guard !visiblePageRect.isNull, !visiblePageRect.isEmpty else { continue }

                let patternColor: Color
                if let tint = style.paperTint {
                    let ink = PageBackgroundStyle.patternInk(forTint: tint, opacity: 0.12)
                    patternColor = Color(red: ink.red, green: ink.green, blue: ink.blue)
                        .opacity(ink.alpha)
                } else {
                    patternColor = VellumTheme.ink(0.12)
                }

                var pageContext = context
                pageContext.clip(to: Path(viewPageRect))
                if !pdfBands.contains(index) {
                    let marks = PageBackgroundPattern.marks(
                        style: style,
                        pageRect: contentPageRect,
                        clippedTo: visiblePageRect
                    )
                    switch marks {
                    case .none:
                        break
                    case .dots(let xs, let ys):
                        let dotRadius = max(0.5, min(2, viewport.zoomScale))
                        var dots = Path()

                        for x in xs.values {
                            for y in ys.values {
                                let viewPoint = viewport.viewPoint(
                                    fromContent: CGPoint(x: x, y: y)
                                )
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

                        pageContext.fill(dots, with: .color(patternColor))
                    case .rules(let ys, let columns):
                        var lines = Path()

                        for y in ys.values {
                            let start = viewport.viewPoint(
                                fromContent: CGPoint(x: contentPageRect.minX, y: y)
                            )
                            let end = viewport.viewPoint(
                                fromContent: CGPoint(x: contentPageRect.maxX, y: y)
                            )
                            let snappedY = (round(start.y * displayScale) / displayScale)
                                + 0.5 / displayScale
                            lines.move(to: CGPoint(x: start.x, y: snappedY))
                            lines.addLine(to: CGPoint(x: end.x, y: snappedY))
                        }

                        if let xs = columns {
                            for x in xs.values {
                                let start = viewport.viewPoint(
                                    fromContent: CGPoint(x: x, y: contentPageRect.minY)
                                )
                                let end = viewport.viewPoint(
                                    fromContent: CGPoint(x: x, y: contentPageRect.maxY)
                                )
                                let snappedX = (round(start.x * displayScale) / displayScale)
                                    + 0.5 / displayScale
                                lines.move(to: CGPoint(x: snappedX, y: start.y))
                                lines.addLine(to: CGPoint(x: snappedX, y: end.y))
                            }
                        }

                        pageContext.stroke(
                            lines,
                            with: .color(patternColor),
                            lineWidth: 1
                        )
                    }
                }
                if !pdfBands.contains(index) {
                    pageContext.draw(
                        Text("\(index + 1)")
                            .font(.vellumMono(10))
                            .foregroundStyle(VellumTheme.ink(0.25)),
                        at: CGPoint(x: viewPageRect.maxX - 8, y: viewPageRect.minY + 8),
                        anchor: .topTrailing
                    )
                    context.stroke(
                        Path(viewPageRect),
                        with: .color(VellumTheme.ink(0.18)),
                        lineWidth: 1
                    )
                }
            }

            guard case .background = mode else { return }
            if firstVisible < lastVisible {
                for index in firstVisible..<lastVisible {
                    let contentPageRect = geometry.pageRect(index: index)
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
        .vellumFloatingChrome(.pill(variant: 3))
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
        .vellumFloatingChrome(.pill(variant: 0))
    }
}
