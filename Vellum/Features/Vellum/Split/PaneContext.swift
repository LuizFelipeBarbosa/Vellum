import CoreGraphics

@MainActor
struct PaneContext {
    let pane: NotePane
    let isFocused: Bool
    let isFirstPane: Bool
    let paneWidth: CGFloat
    let paneCount: Int
    let onClose: () -> Void
    let onFocus: () -> Void
}
