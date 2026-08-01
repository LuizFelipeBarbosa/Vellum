import SwiftUI

/// This leaf is the only drag view that observes location. Keeping that read
/// here prevents the expensive pane container from being invalidated at 120 Hz.
@MainActor
struct FloatingDragCardView: View {
    let session: SplitDragSession
    let commitFrame: CGRect?

    var body: some View {
        if let lift = session.lift {
            let isCommitting = session.isCommitting
            let location = session.location
            let targetPosition = if isCommitting, let commitFrame {
                CGPoint(x: commitFrame.midX, y: commitFrame.midY)
            } else {
                CGPoint(
                    x: location.x - lift.grabOffset.width,
                    y: location.y - lift.grabOffset.height
                )
            }

            NoteDragPreviewCard(
                title: lift.title,
                spaceColor: lift.spaceColor,
                expandedSize: isCommitting ? commitFrame?.size : nil
            )
            .position(targetPosition)
            .opacity(session.resolution?.target == nil ? 1 : 0.6)
            .scaleEffect(session.isLifted ? 1 : 0.98)
            .allowsHitTesting(false)
        }
    }
}
