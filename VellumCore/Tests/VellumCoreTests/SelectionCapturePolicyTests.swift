import Testing
@testable import VellumCore

@Suite("Selection capture policy")
struct SelectionCapturePolicyTests {
    @Test("Any pointer moves an existing selection, with or without finger capture")
    func anyPointerMovesExistingSelection() {
        for pointer in [CapturePointerKind.pencil, .finger] {
            for allowsFingerCapture in [false, true] {
                #expect(
                    SelectionCapturePolicy.dragIntent(
                        pointer: pointer,
                        hasSelection: true,
                        allowsFingerCapture: allowsFingerCapture
                    ) == .move
                )
            }
        }
    }

    @Test("Pencil drags start a capture when nothing is selected")
    func pencilDragsCaptureWithoutSelection() {
        for allowsFingerCapture in [false, true] {
            #expect(
                SelectionCapturePolicy.dragIntent(
                    pointer: .pencil,
                    hasSelection: false,
                    allowsFingerCapture: allowsFingerCapture
                ) == .capture
            )
        }
    }

    @Test("Finger drags start a capture with nothing selected when finger capture is enabled")
    func fingerDragsCaptureWhenEnabled() {
        #expect(
            SelectionCapturePolicy.dragIntent(
                pointer: .finger,
                hasSelection: false,
                allowsFingerCapture: true
            ) == .capture
        )
    }

    @Test("Finger drags scroll the canvas with nothing selected when finger capture is disabled")
    func fingerDragsFallThroughWhenDisabled() {
        #expect(
            SelectionCapturePolicy.dragIntent(
                pointer: .finger,
                hasSelection: false,
                allowsFingerCapture: false
            ) == nil
        )
    }
}
