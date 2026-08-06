import SwiftUI

struct SelectionPasteBubbleView: View {
    let onPaste: () -> Void
    static let bubbleSize = CGSize(width: 96, height: 36)

    /// Centers the bubble 12pt above the view-space tap point, clamped to the viewport with an
    /// 8pt margin. Pure; unit tested.
    static func position(forTapAt viewPoint: CGPoint, in viewportSize: CGSize) -> CGPoint {
        let margin: CGFloat = 8

        let x: CGFloat
        if viewportSize.width < bubbleSize.width + margin * 2 {
            x = viewportSize.width / 2
        } else {
            x = min(
                max(viewPoint.x, bubbleSize.width / 2 + margin),
                viewportSize.width - bubbleSize.width / 2 - margin
            )
        }

        let desiredY = viewPoint.y - 12 - bubbleSize.height / 2
        let y: CGFloat
        if viewportSize.height < bubbleSize.height + margin * 2 {
            y = viewportSize.height / 2
        } else {
            y = min(
                max(desiredY, bubbleSize.height / 2 + margin),
                viewportSize.height - bubbleSize.height / 2 - margin
            )
        }

        return CGPoint(x: x, y: y)
    }

    var body: some View {
        Button(action: onPaste) {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(VellumTheme.mutedDark)
        .frame(width: Self.bubbleSize.width, height: Self.bubbleSize.height)
        .vellumFloatingChrome(.pill(variant: 0))
        .accessibilityLabel("Paste here")
    }
}
