import SwiftUI
import UIKit
import VellumCore

@MainActor
struct SplitDragState {
    let dragID: UUID
    let noteID: UUID
    let title: String
    let spaceColor: Color?
    var location: CGPoint
    var target: SplitGridDropTarget?
}

@MainActor
struct SplitSidebarRowDragGesture: UIGestureRecognizerRepresentable {
    let noteIDs: [UUID]
    let onBegin: (UUID, CGPoint) -> Void
    let onMove: (CGPoint) -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var noteIDForTouch: ((UIGestureRecognizer, UITouch) -> UUID?)?
        var activeNoteID: UUID?

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            let noteID = noteIDForTouch?(gestureRecognizer, touch)

            // The first eligible touch fixes the dragged row while the press
            // is still possible. A second finger can land on a different row
            // before the long press resolves and must not retarget the drag.
            if gestureRecognizer.state == .possible, activeNoteID == nil {
                activeNoteID = noteID
            }

            return noteID != nil
        }

        // Row selection is a SwiftUI Button whose tap recognizer would
        // otherwise claim note touches outright; requiring it to wait for
        // the long press to fail makes hold-to-drag win while quick taps
        // still open. Scroll pans stay exempt so scrolling never waits out
        // the press delay. Invariant: every non-pan recognizer in this
        // subtree waits out the long press.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            !(other is UIPanGestureRecognizer)
        }
    }

    func makeCoordinator(
        converter: CoordinateSpaceConverter
    ) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(
        context: Context
    ) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        context.coordinator.noteIDForTouch = gate
        recognizer.delegate = context.coordinator
        configure(recognizer)
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        context.coordinator.noteIDForTouch = gate
        configure(recognizer)
    }

    // Gating happens before the recognizer owns the touch, so the SwiftUI
    // converter is unavailable. The nearest backing UIScrollView supplies
    // content-space coordinates directly because scrolling changes its
    // bounds origin, and avoids rotation-sensitive window coordinates.
    private var gate: (UIGestureRecognizer, UITouch) -> UUID? {
        { _, touch in
            var probe = touch.view
            while let view = probe, !(view is UIScrollView) {
                probe = view.superview
            }
            guard let scrollView = probe,
                  let rowIndex = SplitSidebarDragMath.rowIndex(
                    forContentY: touch.location(in: scrollView).y,
                    rowCount: noteIDs.count
                  ) else {
                return nil
            }
            return noteIDs[rowIndex]
        }
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        switch recognizer.state {
        case .began:
            guard let noteID = context.coordinator.activeNoteID else {
                onCancel()
                return
            }
            onBegin(noteID, convertedLocation(context: context))
        case .changed:
            onMove(convertedLocation(context: context))
        case .ended:
            onEnd()
            context.coordinator.activeNoteID = nil
        case .cancelled, .failed:
            onCancel()
            context.coordinator.activeNoteID = nil
        case .possible:
            break
        @unknown default:
            onCancel()
            context.coordinator.activeNoteID = nil
        }
    }

    private func configure(_ recognizer: UILongPressGestureRecognizer) {
        recognizer.minimumPressDuration = 0.3
        recognizer.numberOfTouchesRequired = 1
        recognizer.cancelsTouchesInView = true
        recognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
        ]
    }

    private func convertedLocation(context: Context) -> CGPoint {
        context.converter.location(in: .named("splitContainer"))
    }
}

@MainActor
struct NoteDragPreviewCard: View {
    let title: String
    let spaceColor: Color?

    var body: some View {
        HStack(spacing: 8) {
            if let spaceColor {
                Circle()
                    .fill(spaceColor)
                    .frame(width: 7, height: 7)
            }

            Text(title)
                .font(.vellumNewsreader(15, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 180, alignment: .leading)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.18), radius: 18, x: -4, y: 12)
        .scaleEffect(1.03)
        .allowsHitTesting(false)
    }
}
