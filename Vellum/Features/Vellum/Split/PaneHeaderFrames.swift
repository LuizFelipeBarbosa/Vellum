import Foundation
import SwiftUI

/// The header geometry a pane reports upward. `NoteScreenView` writes it as a
/// preference and `NoteSplitContainerView` reads it back to place the sidebar
/// toggle and to keep the docked toolbar clear of the navbar.
struct PaneHeaderFrames: Equatable, Sendable {
    var leftClusterFrame: CGRect
    var rightClusterFrame: CGRect
    var topOverlayGlobalFrame: CGRect
}

struct PaneHeaderFramesKey: PreferenceKey {
    static let defaultValue: [UUID: PaneHeaderFrames] = [:]

    static func reduce(
        value: inout [UUID: PaneHeaderFrames],
        nextValue: () -> [UUID: PaneHeaderFrames]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
