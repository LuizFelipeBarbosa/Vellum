import SwiftUI
import UIKit
import VellumCore

struct SplitDragLift: Equatable {
    let dragID: UUID
    let noteID: UUID
    let title: String
    let spaceColor: Color?
    var grabOffset: CGSize
}

enum SidebarDropResolution: Equatable {
    case cancelZone
    case capacityFull
    case target(SplitGridDropTarget)
}

@MainActor
private final class SplitSidebarLongPressGestureRecognizer:
    UILongPressGestureRecognizer {
    var onReset: (() -> Void)?

    override func reset() {
        super.reset()
        // UIKit does not send an action when a pending press fails. Reset is
        // the one lifecycle hook that also covers that possible-to-failed path.
        onReset?()
    }
}

@MainActor
struct SplitSidebarRowDragGesture: UIGestureRecognizerRepresentable {
    let noteIDs: [UUID]
    let onPrepare: () -> Void
    let onBegin: (UUID, CGPoint) -> Void
    let onMove: (CGPoint) -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var noteIDForTouch: ((UIScrollView, UITouch) -> UUID?)?
        var activeNoteID: UUID?
        private weak var scrollView: UIScrollView?
        private weak var lockedScrollView: UIScrollView?
        private var wasScrollEnabled: Bool?

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // Gating happens before the recognizer owns the touch, so the
            // SwiftUI converter is unavailable. The nearest backing scroll
            // view supplies content-space coordinates directly because
            // scrolling changes its bounds origin, and avoids
            // rotation-sensitive window coordinates.
            var probe = touch.view
            while let view = probe, !(view is UIScrollView) {
                probe = view.superview
            }
            guard let scrollView = probe as? UIScrollView else { return false }
            self.scrollView = scrollView
            let noteID = noteIDForTouch?(scrollView, touch)

            // The first eligible touch fixes the dragged row while the press
            // is still possible. A second finger can land on a different row
            // before the long press resolves and must not retarget the drag.
            if gestureRecognizer.state == .possible, activeNoteID == nil {
                activeNoteID = noteID
            }

            return noteID != nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // Recognizing simultaneously with the scroll pan leaves nothing to fail
        // the press once a scroll has started, and allowableMovement alone lets
        // a slow scroll linger inside the press's window. This runs exactly at
        // the press's possible-to-began transition, so refusing here sends it to
        // failed and a list that is already moving keeps its touch.
        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let scrollView else { return true }
            return !scrollView.isDragging && !scrollView.isDecelerating
        }

        // Row selection is a SwiftUI Button whose tap recognizer would
        // otherwise claim note touches outright; requiring it to wait for
        // the long press to fail makes hold-to-drag win while quick taps
        // still open. Scroll pans stay exempt and recognize simultaneously,
        // so ordinary scrolling starts immediately; the scroll view is
        // locked only after the long press lifts a row. Invariant: every
        // non-pan recognizer in this subtree waits out the long press.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            !(other is UIPanGestureRecognizer)
        }

        func lockScrolling() {
            guard lockedScrollView == nil, let scrollView else { return }
            lockedScrollView = scrollView
            wasScrollEnabled = scrollView.isScrollEnabled
            scrollView.isScrollEnabled = false
        }

        func restoreScrolling() {
            if let wasScrollEnabled {
                lockedScrollView?.isScrollEnabled = wasScrollEnabled
            }
            lockedScrollView = nil
            wasScrollEnabled = nil
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
        let recognizer = SplitSidebarLongPressGestureRecognizer()
        context.coordinator.noteIDForTouch = gate
        recognizer.delegate = context.coordinator
        recognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
        ]
        recognizer.onReset = {
            context.coordinator.activeNoteID = nil
        }
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

    private var gate: (UIScrollView, UITouch) -> UUID? {
        { scrollView, touch in
            guard let rowIndex = RowDragMath.rowIndex(
                forContentY: touch.location(in: scrollView).y,
                rowHeight: SplitSidebarLayout.rowHeight,
                rowCount: noteIDs.count
            ) else {
                return nil
            }
            onPrepare()
            return noteIDs[rowIndex]
        }
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        switch recognizer.state {
        case .began:
            context.coordinator.lockScrolling()
            guard let noteID = context.coordinator.activeNoteID else {
                onCancel()
                return
            }
            onBegin(noteID, convertedLocation(context: context))
        case .changed:
            onMove(convertedLocation(context: context))
        case .ended:
            context.coordinator.restoreScrolling()
            onEnd()
        case .cancelled, .failed:
            context.coordinator.restoreScrolling()
            onCancel()
        case .possible:
            break
        @unknown default:
            context.coordinator.restoreScrolling()
            onCancel()
        }
    }

    private func configure(_ recognizer: UILongPressGestureRecognizer) {
        recognizer.minimumPressDuration = 0.3
        recognizer.allowableMovement = 24
        recognizer.numberOfTouchesRequired = 1
        recognizer.cancelsTouchesInView = true
    }

    private func convertedLocation(context: Context) -> CGPoint {
        context.converter.location(in: .named("splitContainer"))
    }
}

struct NoteGhostLabel: View {
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
    }
}

struct NoteDragPreviewCard: View {
    let title: String
    let spaceColor: Color?
    var expandedSize: CGSize? = nil

    var body: some View {
        NoteGhostLabel(title: title, spaceColor: spaceColor)
        .padding(14)
        .frame(
            width: expandedSize?.width ?? 180,
            height: expandedSize?.height,
            alignment: .topLeading
        )
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.18), radius: 18, x: -4, y: 12)
        .scaleEffect(expandedSize == nil ? 1.03 : 1)
        .allowsHitTesting(false)
    }
}
