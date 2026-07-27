import CoreGraphics
import Testing
@testable import VellumCore

@Suite("Selection capture policy")
struct SelectionCapturePolicyTests {
    /// A snapped horizontal line: wide, and only as tall as the minimum frame a shape gets.
    /// It is the case the padded grab area exists for — there is no interior to aim at.
    private let lineBounds = CGRect(x: 100, y: 200, width: 120, height: 8)

    @Test("A drag beginning beside a small selection moves it, from any pointer")
    func dragInsidePaddedAreaMovesSelection() {
        // Ten points below the line's bounds: outside the shape itself, inside the touch target.
        let besideLine = CGPoint(x: lineBounds.midX, y: lineBounds.maxY + 10)

        for pointer in [CapturePointerKind.pencil, .finger] {
            for allowsFingerCapture in [false, true] {
                #expect(
                    dragIntent(
                        pointer,
                        at: besideLine,
                        selectionBounds: lineBounds,
                        allowsFingerCapture: allowsFingerCapture
                    ) == .move
                )
            }
        }
    }

    @Test("Past the grab area a pencil captures and a finger scrolls unless it may capture")
    func dragOutsidePaddedAreaLeavesSelectionAlone() {
        // Thirty-two points below the bounds, half again as far as the padding reaches.
        let awayFromLine = CGPoint(x: lineBounds.midX, y: lineBounds.maxY + 32)

        for allowsFingerCapture in [false, true] {
            #expect(
                dragIntent(
                    .pencil,
                    at: awayFromLine,
                    selectionBounds: lineBounds,
                    allowsFingerCapture: allowsFingerCapture
                ) == .capture
            )
        }
        #expect(
            dragIntent(
                .finger,
                at: awayFromLine,
                selectionBounds: lineBounds,
                allowsFingerCapture: true
            ) == .capture
        )
        #expect(
            dragIntent(
                .finger,
                at: awayFromLine,
                selectionBounds: lineBounds,
                allowsFingerCapture: false
            ) == nil
        )
    }

    @Test("The grab area is measured on screen, so zooming out widens it in content space")
    func grabAreaFollowsZoom() {
        // The same content-space point is sixteen screen points from the bounds at half zoom —
        // within the target — and sixty-four at double zoom, far outside it.
        let awayFromLine = CGPoint(x: lineBounds.midX, y: lineBounds.maxY + 32)

        #expect(
            dragIntent(
                .finger,
                at: awayFromLine,
                selectionBounds: lineBounds,
                zoomScale: 0.5,
                allowsFingerCapture: false
            ) == .move
        )
        #expect(
            dragIntent(
                .finger,
                at: awayFromLine,
                selectionBounds: lineBounds,
                zoomScale: 2,
                allowsFingerCapture: false
            ) == nil
        )
    }

    @Test("A selection with no extent still offers the whole touch target")
    func zeroSizedSelectionFillsMinimumTarget() {
        let dot = CGRect(x: 60, y: 60, width: 0, height: 0)
        let area = SelectionCapturePolicy.grabArea(around: dot, zoomScale: 2)

        // Content extent times the zoom is what the user's finger sees.
        #expect(area.width * 2 == SelectionCapturePolicy.minimumGrabTarget)
        #expect(area.height * 2 == SelectionCapturePolicy.minimumGrabTarget)
        #expect(
            dragIntent(
                .finger,
                at: CGPoint(x: dot.midX + 10, y: dot.midY),
                selectionBounds: dot,
                zoomScale: 2,
                allowsFingerCapture: false
            ) == .move
        )
        #expect(
            dragIntent(
                .finger,
                at: CGPoint(x: dot.midX + 12, y: dot.midY),
                selectionBounds: dot,
                zoomScale: 2,
                allowsFingerCapture: false
            ) == nil
        )
    }

    /// Bounds go missing either because nothing is selected or because a selection outlived the
    /// geometry that gave it bounds — deleting the page an element sat on does that. Neither
    /// leaves anything on screen to grab, so both behave the same: the pointer decides.
    @Test("With no bounds to grab, the pointer alone decides what the drag does")
    func missingBoundsLeaveTheDragToThePointer() {
        let anywhere = CGPoint(x: 160, y: 204)

        for allowsFingerCapture in [false, true] {
            #expect(
                dragIntent(
                    .pencil,
                    at: anywhere,
                    selectionBounds: nil,
                    allowsFingerCapture: allowsFingerCapture
                ) == .capture
            )
        }
        #expect(
            dragIntent(
                .finger,
                at: anywhere,
                selectionBounds: nil,
                allowsFingerCapture: true
            ) == .capture
        )
        #expect(
            dragIntent(
                .finger,
                at: anywhere,
                selectionBounds: nil,
                allowsFingerCapture: false
            ) == nil
        )
    }

    private func dragIntent(
        _ pointer: CapturePointerKind,
        at location: CGPoint,
        selectionBounds: CGRect?,
        zoomScale: CGFloat = 1,
        allowsFingerCapture: Bool
    ) -> SelectionDragIntent? {
        SelectionCapturePolicy.dragIntent(
            pointer: pointer,
            location: location,
            selectionBounds: selectionBounds,
            zoomScale: zoomScale,
            allowsFingerCapture: allowsFingerCapture
        )
    }
}
