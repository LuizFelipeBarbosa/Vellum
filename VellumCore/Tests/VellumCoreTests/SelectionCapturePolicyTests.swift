import Testing
@testable import VellumCore

@Suite("Selection capture policy")
struct SelectionCapturePolicyTests {
    @Test("Pencil drags are always allowed")
    func pencilDragsAreAlwaysAllowed() {
        for insideSelection in [false, true] {
            for allowsFingerCapture in [false, true] {
                #expect(
                    SelectionCapturePolicy.allowsDrag(
                        pointer: .pencil,
                        insideSelection: insideSelection,
                        allowsFingerCapture: allowsFingerCapture
                    )
                )
            }
        }
    }

    @Test("Finger drags inside a selection are allowed for moves")
    func fingerDragsInsideSelectionAreAllowed() {
        #expect(
            SelectionCapturePolicy.allowsDrag(
                pointer: .finger,
                insideSelection: true,
                allowsFingerCapture: false
            )
        )
    }

    @Test("Finger drags outside a selection are allowed when finger capture is enabled")
    func fingerDragsOutsideSelectionAreAllowedWhenEnabled() {
        #expect(
            SelectionCapturePolicy.allowsDrag(
                pointer: .finger,
                insideSelection: false,
                allowsFingerCapture: true
            )
        )
    }

    @Test("Finger drags outside a selection are denied when finger capture is disabled")
    func fingerDragsOutsideSelectionAreDeniedWhenDisabled() {
        #expect(
            !SelectionCapturePolicy.allowsDrag(
                pointer: .finger,
                insideSelection: false,
                allowsFingerCapture: false
            )
        )
    }
}
