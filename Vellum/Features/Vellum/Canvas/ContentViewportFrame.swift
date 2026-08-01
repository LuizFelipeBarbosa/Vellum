import SwiftUI

/// Places a content-space layer inside a viewport: sizes it to the full content,
/// applies the canvas zoom and scroll offset, then clips it back to the viewport.
///
/// Applied to every overlay that has to track the PencilKit canvas pixel for
/// pixel — element bands above and below the ink, and the selection overlay.
private struct ContentViewportFrameModifier: ViewModifier {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let zoom: CGFloat
    let contentOffset: CGPoint
    let viewportSize: CGSize

    func body(content: Content) -> some View {
        content
            .frame(
                width: contentWidth,
                height: contentHeight,
                alignment: .topLeading
            )
            .scaleEffect(zoom, anchor: .topLeading)
            .offset(
                x: -contentOffset.x,
                y: -contentOffset.y
            )
            .frame(
                width: viewportSize.width,
                height: viewportSize.height,
                alignment: .topLeading
            )
            .clipped()
    }
}

extension View {
    func contentViewportFrame(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        zoom: CGFloat,
        contentOffset: CGPoint,
        viewportSize: CGSize
    ) -> some View {
        modifier(
            ContentViewportFrameModifier(
                contentWidth: contentWidth,
                contentHeight: contentHeight,
                zoom: zoom,
                contentOffset: contentOffset,
                viewportSize: viewportSize
            )
        )
    }
}
