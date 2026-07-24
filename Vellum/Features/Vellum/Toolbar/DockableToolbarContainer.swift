import SwiftUI
import VellumCore

struct TopDockObstructions: Equatable {
    var navbarTop: CGFloat
    var overlayBottom: CGFloat
    var gapMinX: CGFloat
    var gapMaxX: CGFloat
}

struct DockableToolbarContainer<Content: View>: View {
    let store: ToolPreferencesStore
    let containerSize: CGSize
    let topObstructions: TopDockObstructions?
    @ViewBuilder let content: (ToolbarDockEdge, CGFloat) -> Content

    @State private var toolbarSize: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero

    private var baseInsets: DockInsets {
        DockInsets(
            top: (topObstructions?.overlayBottom ?? 0) + 12,
            leading: 12,
            bottom: 24,
            trailing: 12
        )
    }

    private var placementInsets: (insets: DockInsets, edgeMargin: CGFloat) {
        let placement = store.preferences.toolbarDock
        guard placement.edge == .top,
              let obs = topObstructions else { return (baseInsets, 16) }
        let gapWidth = obs.gapMaxX - obs.gapMinX - 24
        guard toolbarSize.width > 0,
              toolbarSize.width <= gapWidth else { return (baseInsets, 16) }
        return (
            DockInsets(
                top: obs.navbarTop,
                leading: obs.gapMinX + 12,
                bottom: 24,
                trailing: containerSize.width - obs.gapMaxX + 12
            ),
            0
        )
    }

    private var dockedCenter: CGPoint {
        let resolved = placementInsets
        return ToolbarDockPolicy.center(
            of: store.preferences.toolbarDock,
            toolbarSize: toolbarSize,
            container: containerSize,
            insets: resolved.insets,
            edgeMargin: resolved.edgeMargin
        )
    }

    var body: some View {
        let dockEdge = store.preferences.toolbarDock.edge
        let availableAxisLength = dockEdge.axis == .vertical
            ? containerSize.height - baseInsets.top - baseInsets.bottom - 2 * 16
            : containerSize.width - baseInsets.leading - baseInsets.trailing - 2 * 16
        content(dockEdge, availableAxisLength)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                toolbarSize = newSize
            }
            .position(
                x: dockedCenter.x + dragTranslation.width,
                y: dockedCenter.y + dragTranslation.height
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toolbarSize)
            .animation(
                .spring(response: 0.35, dampingFraction: 0.8),
                value: store.preferences.toolbarDock
            )
            // .gesture (not .simultaneousGesture): child ScrollViews (favorite
            // colors) must win their pans outright, or scrolling them would also
            // accumulate dragTranslation and commit a dock change on release.
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        dragTranslation = value.translation
                    }
                    .onEnded { value in
                        let releaseCenter = CGPoint(
                            x: dockedCenter.x + value.translation.width,
                            y: dockedCenter.y + value.translation.height
                        )
                        let placement = ToolbarDockPolicy.nearestPlacement(
                            releaseCenter: releaseCenter,
                            toolbarSize: toolbarSize,
                            container: containerSize,
                            insets: baseInsets
                        )
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            dragTranslation = .zero
                            store.update { $0.toolbarDock = placement }
                        }
                    }
            )
    }
}
