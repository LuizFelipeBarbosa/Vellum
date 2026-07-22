import CoreGraphics
import Observation
import VellumCore

@MainActor
@Observable
final class NotePageState {
    /// With no content, starts with one drawable page and one blank page ahead.
    private(set) var pageCount = PageLayout.pageCount(forContentBottom: 0)
    private(set) var currentPageIndex = 0

    var contentHeight: CGFloat {
        PageLayout.contentHeight(pageCount: pageCount)
    }

    /// Recomputes the page count from the deepest ink or element.
    func updateContent(drawingBounds: CGRect, elements: [CanvasElement]) {
        let drawingBottom =
            (drawingBounds.isNull || drawingBounds.isEmpty) ? 0 : drawingBounds.maxY
        let elementsBottom = elements
            .map { $0.effectiveBoundingBox.maxY }
            .max() ?? 0
        let bottom = max(drawingBottom, elementsBottom)
        let newCount = PageLayout.pageCount(forContentBottom: bottom)
        guard newCount != pageCount else { return }
        pageCount = newCount
    }

    /// Recomputes the current page from the visible content rectangle's midpoint.
    func updateViewport(_ viewport: CanvasViewport, viewportSize: CGSize) {
        let midY = viewport.visibleContentRect(viewportSize: viewportSize).midY
        let newIndex = PageLayout.pageIndex(forContentY: midY, pageCount: pageCount)
        guard newIndex != currentPageIndex else { return }
        currentPageIndex = newIndex
    }
}
