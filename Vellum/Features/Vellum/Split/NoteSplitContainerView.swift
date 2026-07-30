import Foundation
import Observation
import SwiftUI
import VellumCore

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

private enum SidebarDropResolution {
    case cancelZone
    case capacityFull
    case target(SplitDropTarget)
}

@MainActor
struct NoteSplitContainerView: View {
    @Bindable var app: VellumAppModel
    @State private var fallbackCanvasReference = NoteCanvasReference()
    @State private var paneHeaderFrames: [UUID: PaneHeaderFrames] = [:]
    @State private var isShowingNoteSidebar = false
    @State private var dragState: SplitDragState?

    private var noteSidebarWidth: CGFloat { 300 }
    private var noteSidebarOuterPadding: CGFloat { 18 }
    private var noteSidebarCancelZoneMaxX: CGFloat {
        noteSidebarOuterPadding + noteSidebarWidth + noteSidebarOuterPadding
    }

    var body: some View {
        GeometryReader { geometry in
            let panes = app.split.panes
            let focusedPane = app.split.focusedPane
            let paneWidths = SplitLayoutPolicy.paneWidths(
                fractions: panes.map(\.widthFraction),
                containerWidth: geometry.size.width
            )
            let focusedPaneIndex = panes.firstIndex {
                $0.id == app.split.focusedPaneID
            } ?? -1
            let containerGlobalOrigin = geometry.frame(in: .global).origin
            let firstPaneHeaderFrames = panes.first.flatMap {
                paneHeaderFrames[$0.id]
            }

            ZStack(alignment: .topLeading) {
                if panes.isEmpty {
                    ProgressView("Loading note…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(panes.enumerated()), id: \.element.id) { entry in
                            let index = entry.offset
                            let pane = entry.element
                            let paneID = pane.id
                            let appModel = app

                            NoteScreenView(
                                model: pane.noteModel,
                                app: appModel,
                                paneContext: PaneContext(
                                    pane: pane,
                                    isFocused: app.split.focusedPaneID == paneID,
                                    isFirstPane: index == 0,
                                    paneWidth: paneWidths[index],
                                    paneCount: panes.count,
                                    onClose: { [weak appModel] in
                                        guard let appModel else { return }
                                        Task {
                                            await appModel.closePane(paneID)
                                        }
                                    },
                                    onFocus: { [weak appModel] in
                                        appModel?.split.focus(paneID)
                                    }
                                )
                            )
                            .frame(width: paneWidths[index])
                            .clipped()
                        }
                    }
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .leading
                    )
                }

                if panes.count > 1 {
                    ForEach(0..<(panes.count - 1), id: \.self) { dividerIndex in
                        PaneDividerView(
                            app: app,
                            dividerIndex: dividerIndex,
                            containerWidth: geometry.size.width
                        )
                        .frame(height: geometry.size.height)
                        .position(
                            x: paneWidths.prefix(dividerIndex + 1).reduce(0, +),
                            y: geometry.size.height / 2
                        )
                    }
                }

                DockableToolbarContainer(
                    store: app.toolPreferences,
                    containerSize: geometry.size,
                    topObstructions: topDockObstructions(
                        for: app.split.focusedPaneID.flatMap { paneHeaderFrames[$0] },
                        containerGlobalOrigin: geometry.frame(in: .global).origin
                    )
                ) { dockEdge, availableAxisLength in
                    NoteToolbarView(
                        store: app.toolPreferences,
                        selectedTool: Binding(
                            get: { app.split.selectedTool },
                            set: { app.split.selectedTool = $0 }
                        ),
                        activeOptionsTool: Binding(
                            get: { app.split.activeOptionsTool },
                            set: { app.split.activeOptionsTool = $0 }
                        ),
                        canvasReference: focusedPane?.canvasReference
                            ?? fallbackCanvasReference,
                        backgroundStyle: focusedPane.map { pane in
                            Binding(
                                get: { pane.noteModel.backgroundStyle },
                                set: { pane.noteModel.backgroundStyle = $0 }
                            )
                        },
                        onInsertPhoto: {
                            app.split.focusedPane?.noteModel.isShowingPhotosPicker = true
                        },
                        onInsertFile: {
                            app.split.focusedPane?.noteModel.isShowingFileImporter = true
                        },
                        dockEdge: dockEdge,
                        availableAxisLength: availableAxisLength
                    )
                }
                .zIndex(4)

                edgeSwipeSurface(containerHeight: geometry.size.height)
                    .zIndex(5)

                noteSidebarToggle
                    .position(
                        sidebarToggleCenter(
                            for: firstPaneHeaderFrames,
                            containerGlobalOrigin: containerGlobalOrigin
                        )
                    )
                    .zIndex(isShowingNoteSidebar ? 9 : 5)

                dragDropIndicator(
                    paneWidths: paneWidths,
                    containerSize: geometry.size
                )
                .zIndex(6)

                if isShowingNoteSidebar {
                    noteSidebarOverlay(containerWidth: geometry.size.width)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(8)
                }

                if let dragState {
                    NoteDragPreviewCard(
                        title: dragState.title,
                        spaceColor: dragState.spaceColor
                    )
                    .position(dragState.location)
                    .zIndex(10)
                }

                Color.clear
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("vellum-split-state")
                    .accessibilityValue(
                        "panes:\(panes.count);"
                            + "fractions:\(formattedFractions(panes));"
                            + "focused:\(focusedPaneIndex);"
                            + "dragging:\(dragState == nil ? 0 : 1);"
                            + "target:\(formattedDragTarget(dragState?.target))"
                    )
            }
            .coordinateSpace(name: "splitContainer")
            .onPreferenceChange(PaneHeaderFramesKey.self) {
                paneHeaderFrames = $0
            }
            .animation(.easeOut(duration: 0.2), value: isShowingNoteSidebar)
        }
        .task {
            app.split.selectedTool = app.toolPreferences.preferences.lastSelectedTool
        }
        .onChange(of: app.split.selectedTool) { _, newTool in
            app.toolPreferences.update { preferences in
                preferences.lastSelectedTool = newTool
            }
        }
    }

    private var noteSidebarToggle: some View {
        Button {
            isShowingNoteSidebar.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VellumTheme.accentDark)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            VellumTheme.popover,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(VellumTheme.ink(0.12), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
        .accessibilityLabel("Show notes sidebar")
    }

    private func edgeSwipeSurface(containerHeight: CGFloat) -> some View {
        Color.clear
            .frame(width: 20, height: containerHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named("splitContainer")
                )
                .onChanged { value in
                    if value.translation.width > 30 {
                        isShowingNoteSidebar = true
                    }
                }
            )
            .allowsHitTesting(!isShowingNoteSidebar)
    }

    private func noteSidebarOverlay(containerWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissNoteSidebar()
                }

            NoteSplitSidebarView(
                app: app,
                containerWidth: containerWidth,
                onDismiss: dismissNoteSidebar,
                onDragBegan: { summary, spaceColor, location in
                    beginSidebarDrag(
                        noteID: summary.id,
                        title: summary.title.isEmpty ? "Untitled" : summary.title,
                        spaceColor: spaceColor,
                        location: location,
                        containerWidth: containerWidth
                    )
                },
                onDragMoved: { location in
                    moveSidebarDrag(
                        to: location,
                        containerWidth: containerWidth
                    )
                },
                onDragEnded: {
                    endSidebarDrag(containerWidth: containerWidth)
                },
                onDragCancelled: cancelSidebarDrag
            )
            .frame(width: noteSidebarWidth)
            .padding(noteSidebarOuterPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func dragDropIndicator(
        paneWidths: [CGFloat],
        containerSize: CGSize
    ) -> some View {
        switch dragState?.target {
        case .insertBetween(let index):
            Rectangle()
                .fill(VellumTheme.accent)
                .frame(width: 3, height: containerSize.height)
                .position(
                    x: insertionBoundaryX(
                        at: index,
                        paneWidths: paneWidths
                    ),
                    y: containerSize.height / 2
                )
                .allowsHitTesting(false)
        case .existingPane(let index):
            if let rect = paneRect(
                at: index,
                paneWidths: paneWidths,
                containerHeight: containerSize.height
            ) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(VellumTheme.accent(0.55), lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }
        case nil:
            EmptyView()
        }
    }

    private func beginSidebarDrag(
        noteID: UUID,
        title: String,
        spaceColor: Color?,
        location: CGPoint,
        containerWidth: CGFloat
    ) {
        dragState = SplitDragState(
            dragID: UUID(),
            noteID: noteID,
            title: title,
            spaceColor: spaceColor,
            location: location,
            target: sidebarDropResolution(
                for: noteID,
                at: location,
                containerWidth: containerWidth
            ).target
        )
    }

    private func moveSidebarDrag(
        to location: CGPoint,
        containerWidth: CGFloat
    ) {
        guard var state = dragState else { return }
        state.location = location
        state.target = sidebarDropResolution(
            for: state.noteID,
            at: location,
            containerWidth: containerWidth
        ).target
        dragState = state
    }

    private func endSidebarDrag(containerWidth: CGFloat) {
        guard let state = dragState else { return }
        let resolution = sidebarDropResolution(
            for: state.noteID,
            at: state.location,
            containerWidth: containerWidth
        )

        switch resolution {
        case .cancelZone:
            dragState = nil
        case .capacityFull:
            dragState = nil
            app.showToast("Not enough room for another pane")
        case .target(.existingPane(let index)):
            let panes = app.split.panes
            guard panes.indices.contains(index) else {
                dragState = nil
                return
            }
            dragState = nil
            app.split.focus(panes[index].id)
        case .target(.insertBetween(let index)):
            let noteID = state.noteID
            dragState = nil
            isShowingNoteSidebar = false
            Task {
                await app.openNote(
                    noteID,
                    placement: .newPane(at: index)
                )
            }
        }
    }

    private func cancelSidebarDrag() {
        dragState = nil
    }

    private func dismissNoteSidebar() {
        dragState = nil
        isShowingNoteSidebar = false
    }

    private func sidebarDropResolution(
        for noteID: UUID,
        at location: CGPoint,
        containerWidth: CGFloat
    ) -> SidebarDropResolution {
        guard location.x > noteSidebarCancelZoneMaxX else {
            return .cancelZone
        }

        let panes = app.split.panes
        if let existingPaneIndex = panes.firstIndex(
            where: { $0.noteID == noteID }
        ) {
            return .target(.existingPane(index: existingPaneIndex))
        }

        let rawTarget = SplitLayoutPolicy.dropTarget(
            forX: location.x,
            fractions: panes.map(\.widthFraction),
            containerWidth: containerWidth
        )
        let insertionIndex = switch rawTarget {
        case .insertBetween(let index):
            index
        case .existingPane(let index):
            index
        }

        guard panes.count
            < SplitLayoutPolicy.maxPaneCount(
                forContainerWidth: containerWidth
            ) else {
            return .capacityFull
        }
        return .target(.insertBetween(index: insertionIndex))
    }

    private func sidebarToggleCenter(
        for frames: PaneHeaderFrames?,
        containerGlobalOrigin: CGPoint
    ) -> CGPoint {
        let buttonRadius: CGFloat = 22
        let gap: CGFloat = 12
        let fallbackFrame = CGRect(x: 20, y: 10, width: 0, height: 44)
        let leftClusterFrame = if let frames,
                                  frames.leftClusterFrame != .zero {
            frames.leftClusterFrame.offsetBy(
                dx: -containerGlobalOrigin.x,
                dy: -containerGlobalOrigin.y
            )
        } else {
            fallbackFrame
        }
        let topOverlayFrame = if let frames,
                                 frames.topOverlayGlobalFrame != .zero {
            frames.topOverlayGlobalFrame.offsetBy(
                dx: -containerGlobalOrigin.x,
                dy: -containerGlobalOrigin.y
            )
        } else {
            fallbackFrame
        }
        let centerX = isShowingNoteSidebar
            ? noteSidebarCancelZoneMaxX + buttonRadius
            : leftClusterFrame.minX + buttonRadius

        return CGPoint(
            x: centerX,
            y: topOverlayFrame.maxY + gap + buttonRadius
        )
    }

    private func insertionBoundaryX(
        at index: Int,
        paneWidths: [CGFloat]
    ) -> CGFloat {
        paneWidths.prefix(min(max(index, 0), paneWidths.count)).reduce(0, +)
    }

    private func paneRect(
        at index: Int,
        paneWidths: [CGFloat],
        containerHeight: CGFloat
    ) -> CGRect? {
        guard paneWidths.indices.contains(index) else { return nil }
        return CGRect(
            x: paneWidths.prefix(index).reduce(0, +),
            y: 0,
            width: paneWidths[index],
            height: containerHeight
        )
    }

    private func topDockObstructions(
        for frames: PaneHeaderFrames?,
        containerGlobalOrigin: CGPoint
    ) -> TopDockObstructions? {
        guard let frames,
              frames.leftClusterFrame != .zero,
              frames.rightClusterFrame != .zero else {
            return nil
        }
        return TopDockObstructions(
            navbarTop: frames.leftClusterFrame.minY - containerGlobalOrigin.y,
            overlayBottom: frames.topOverlayGlobalFrame.maxY - containerGlobalOrigin.y,
            gapMinX: frames.leftClusterFrame.maxX - containerGlobalOrigin.x,
            gapMaxX: frames.rightClusterFrame.minX - containerGlobalOrigin.x
        )
    }

    private func formattedFractions(_ panes: [NotePane]) -> String {
        panes
            .map {
                String(
                    format: "%.2f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    Double($0.widthFraction)
                )
            }
            .joined(separator: ",")
    }

    private func formattedDragTarget(_ target: SplitDropTarget?) -> String {
        switch target {
        case .insertBetween(let index):
            "insert-\(index)"
        case .existingPane(let index):
            "pane-\(index)"
        case nil:
            "none"
        }
    }
}

private extension SidebarDropResolution {
    var target: SplitDropTarget? {
        if case .target(let target) = self {
            return target
        }
        return nil
    }
}

@MainActor
struct PaneDividerView: View {
    let app: VellumAppModel
    let dividerIndex: Int
    let containerWidth: CGFloat

    @State private var fractionsAtDragStart: [CGFloat]?
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(VellumTheme.ink(0.09))
                .frame(width: 1)

            RoundedRectangle(cornerRadius: 2)
                .fill(isDragging ? VellumTheme.accent : VellumTheme.ink(0.18))
                .frame(width: 4, height: 36)
        }
        .frame(width: SplitLayoutPolicy.dividerHitWidth)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named("splitContainer")
            )
            .onChanged { value in
                let startFractions = fractionsAtDragStart
                    ?? app.split.panes.map(\.widthFraction)
                if fractionsAtDragStart == nil {
                    fractionsAtDragStart = startFractions
                    isDragging = true
                }
                let fractions = SplitLayoutPolicy.fractionsResizing(
                    startFractions,
                    dividerIndex: dividerIndex,
                    byTranslation: value.translation.width,
                    containerWidth: containerWidth
                )
                app.split.applyFractions(fractions)
            }
            .onEnded { _ in
                fractionsAtDragStart = nil
                isDragging = false
            }
        )
    }
}
