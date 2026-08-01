import CoreGraphics
import Testing
@testable import VellumCore

@Test("Rule lines span a full A4 page at the configured spacing")
func ruleLinesSpanFullA4Page() {
    let pageRect = PageGeometry.a4.pageRect(index: 0)
    let style = PageBackgroundStyle(kind: .ruled)
    let stride = PageBackgroundPattern.ruleYs(
        style: style,
        pageRect: pageRect,
        clippedTo: pageRect
    )
    let lastLineIndex = Int((pageRect.height / CGFloat(style.spacing)).rounded(.up)) - 1

    #expect(stride.values.first == pageRect.minY + CGFloat(style.spacing))
    #expect(
        stride.values.last
            == pageRect.minY + CGFloat(lastLineIndex) * CGFloat(style.spacing)
    )
    #expect(stride.values.allSatisfy { $0 < pageRect.maxY })
}

@Test("Patterns align to each page origin")
func patternsAlignToEachPageOrigin() {
    let pageRect = PageGeometry.a4.pageRect(index: 3)
    let style = PageBackgroundStyle(kind: .dots)
    let rules = PageBackgroundPattern.ruleYs(
        style: style,
        pageRect: pageRect,
        clippedTo: pageRect
    )
    let dots = PageBackgroundPattern.dotYs(
        style: style,
        pageRect: pageRect,
        clippedTo: pageRect
    )

    #expect(rules.values.first == pageRect.minY + CGFloat(style.spacing))
    #expect(dots.values.first == pageRect.minY)
}

@Test("Pattern coordinates are clipped to a partially visible page")
func patternCoordinatesClipToPartialVisibility() {
    let pageRect = PageGeometry.a4.pageRect(index: 0)
    let visibleRect = CGRect(x: 0, y: 50, width: pageRect.width, height: 60)
    let stride = PageBackgroundPattern.ruleYs(
        style: PageBackgroundStyle(kind: .ruled),
        pageRect: pageRect,
        clippedTo: visibleRect
    )

    #expect(stride.count == 2)
    #expect(stride.values == [72, 96])
}

@Test("Patterns return no coordinates for a disjoint visible rectangle")
func patternsReturnNoCoordinatesForDisjointVisibility() {
    let pageRect = PageGeometry.a4.pageRect(index: 0)
    let visibleRect = CGRect(
        x: 0,
        y: pageRect.maxY + 100,
        width: pageRect.width,
        height: 100
    )
    let style = PageBackgroundStyle(kind: .grid)

    #expect(PageBackgroundPattern.ruleYs(style: style, pageRect: pageRect, clippedTo: visibleRect).count == 0)
    #expect(PageBackgroundPattern.gridXs(style: style, pageRect: pageRect, clippedTo: visibleRect).count == 0)
    #expect(PageBackgroundPattern.dotXs(style: style, pageRect: pageRect, clippedTo: visibleRect).count == 0)
    #expect(PageBackgroundPattern.dotYs(style: style, pageRect: pageRect, clippedTo: visibleRect).count == 0)
}

@Test("Grid columns exclude both page edges")
func gridColumnsExcludePageEdges() {
    let pageRect = PageGeometry.a4.pageRect(index: 0)
    let stride = PageBackgroundPattern.gridXs(
        style: PageBackgroundStyle(kind: .grid),
        pageRect: pageRect,
        clippedTo: pageRect
    )

    #expect(stride.count == 31)
    #expect(stride.values.first == 24)
    #expect(stride.values.last == 744)
    #expect(!stride.values.contains(pageRect.minX))
    #expect(!stride.values.contains(pageRect.maxX))
}

@Test("Dot lattices include the page origin corner")
func dotLatticesIncludePageOriginCorner() {
    let pageRect = PageGeometry.a4.pageRect(index: 3)
    let style = PageBackgroundStyle(kind: .dots)
    let xs = PageBackgroundPattern.dotXs(style: style, pageRect: pageRect, clippedTo: pageRect)
    let ys = PageBackgroundPattern.dotYs(style: style, pageRect: pageRect, clippedTo: pageRect)

    #expect(xs.values.first == pageRect.minX)
    #expect(ys.values.first == pageRect.minY)
}

@Test("Pattern geometry clamps zero and negative spacing")
func patternGeometryClampsDegenerateSpacing() {
    let pageRect = PageGeometry.a4.pageRect(index: 0)
    var zeroSpacing = PageBackgroundStyle(kind: .grid)
    zeroSpacing.spacing = 0
    var negativeSpacing = PageBackgroundStyle(kind: .dots)
    negativeSpacing.spacing = -100

    let rules = PageBackgroundPattern.ruleYs(
        style: zeroSpacing,
        pageRect: pageRect,
        clippedTo: pageRect
    )
    let columns = PageBackgroundPattern.gridXs(
        style: zeroSpacing,
        pageRect: pageRect,
        clippedTo: pageRect
    )
    let dotXs = PageBackgroundPattern.dotXs(
        style: negativeSpacing,
        pageRect: pageRect,
        clippedTo: pageRect
    )
    let dotYs = PageBackgroundPattern.dotYs(
        style: negativeSpacing,
        pageRect: pageRect,
        clippedTo: pageRect
    )

    #expect(rules.step == 16)
    #expect(columns.step == 16)
    #expect(dotXs.step == 16)
    #expect(dotYs.step == 16)
    #expect(rules.count > 0 && rules.count < 100)
    #expect(columns.count == 47)
    #expect(dotXs.count == 49)
    #expect(dotYs.count > 0 && dotYs.count < 100)
    #expect(rules.values.allSatisfy { $0.isFinite })
    #expect(dotYs.values.allSatisfy { $0.isFinite })
}

@Test("Axis stride values advance from start by step")
func axisStrideValuesAdvanceByStep() {
    let stride = PageBackgroundPattern.AxisStride(start: 10, step: 2.5, count: 4)

    #expect(stride.values == [10, 12.5, 15, 17.5])
}

@Test("Blank paper emits no marks")
func blankPaperEmitsNoMarks() {
    let pageRect = PageGeometry.a4.pageRect(index: 0)

    #expect(
        PageBackgroundPattern.marks(
            style: PageBackgroundStyle(kind: .blank),
            pageRect: pageRect,
            clippedTo: pageRect
        ) == .none
    )
}

@Test("Ruled paper emits rows without columns")
func ruledPaperEmitsRowsOnly() {
    let pageRect = PageGeometry.a4.pageRect(index: 0)
    let style = PageBackgroundStyle(kind: .ruled)

    #expect(
        PageBackgroundPattern.marks(
            style: style,
            pageRect: pageRect,
            clippedTo: pageRect
        )
            == .rules(
                rows: PageBackgroundPattern.ruleYs(
                    style: style,
                    pageRect: pageRect,
                    clippedTo: pageRect
                ),
                columns: nil
            )
    )
}

@Test("Grid paper emits rows and columns")
func gridPaperEmitsRowsAndColumns() {
    let pageRect = PageGeometry.a4.pageRect(index: 0)
    let style = PageBackgroundStyle(kind: .grid)

    #expect(
        PageBackgroundPattern.marks(
            style: style,
            pageRect: pageRect,
            clippedTo: pageRect
        )
            == .rules(
                rows: PageBackgroundPattern.ruleYs(
                    style: style,
                    pageRect: pageRect,
                    clippedTo: pageRect
                ),
                columns: PageBackgroundPattern.gridXs(
                    style: style,
                    pageRect: pageRect,
                    clippedTo: pageRect
                )
            )
    )
}

@Test("Dotted paper emits both dot axes")
func dottedPaperEmitsBothDotAxes() {
    let pageRect = PageGeometry.a4.pageRect(index: 2)
    let style = PageBackgroundStyle(kind: .dots)
    let visibleRect = pageRect.insetBy(dx: 0, dy: pageRect.height / 4)

    #expect(
        PageBackgroundPattern.marks(
            style: style,
            pageRect: pageRect,
            clippedTo: visibleRect
        )
            == .dots(
                xs: PageBackgroundPattern.dotXs(
                    style: style,
                    pageRect: pageRect,
                    clippedTo: visibleRect
                ),
                ys: PageBackgroundPattern.dotYs(
                    style: style,
                    pageRect: pageRect,
                    clippedTo: visibleRect
                )
            )
    )
}
