import CoreGraphics

@MainActor
struct PaneContext {
    let pane: NotePane
    let isFocused: Bool
    let paneWidth: CGFloat
    let paneHeight: CGFloat
    let paneCount: Int
    let onClose: () -> Void
    let onFocus: () -> Void
}
