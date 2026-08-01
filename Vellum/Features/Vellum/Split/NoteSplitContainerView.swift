import Foundation
import SwiftUI
import VellumCore

@MainActor
struct NoteSplitContainerView: View {
    @Bindable var app: VellumAppModel
    @State private var fallbackCanvasReference = NoteCanvasReference()
    @State private var paneHeaderFrames: [UUID: PaneHeaderFrames] = [:]
    @State private var isShowingNoteSidebar = false
    @State private var dragSession = SplitDragSession()
    @State private var dragHaptics = ReorderHaptics()

    var body: some View {
        GeometryReader { geometry in
            let columns = app.split.columns
            let panes = app.split.panes
            let focusedPane = app.split.focusedPane
            let committedGrid = app.split.gridSnapshot
            let lift = dragSession.lift
            let resolution = dragSession.resolution
            let refusedTarget = dragSession.refusedTarget
            let previewTarget = resolution?.target
            let previewGrid = previewTarget.flatMap {
                SplitGridPolicy.gridInserting($0, into: committedGrid)
            } ?? committedGrid
            let committedColumnWidths = SplitGridPolicy.columnWidths(
                grid: committedGrid,
                containerWidth: geometry.size.width
            )
            let committedRowHeights = committedGrid.columns.map {
                SplitGridPolicy.rowHeights(
                    column: $0,
                    containerHeight: geometry.size.height
                )
            }
            let previewColumnWidths = SplitGridPolicy.columnWidths(
                grid: previewGrid,
                containerWidth: geometry.size.width
            )
            let previewRowHeights = previewGrid.columns.map {
                SplitGridPolicy.rowHeights(
                    column: $0,
                    containerHeight: geometry.size.height
                )
            }
            let ghost = SplitContainerLayout.paneGhostConfiguration(
                lift: lift,
                resolution: resolution,
                refusedTarget: refusedTarget,
                committedGrid: committedGrid,
                previewGrid: previewGrid,
                containerSize: geometry.size
            )
            let focusedPaneIndex = app.split.focusedPaneID.flatMap {
                app.split.paneIndex(of: $0)
            }
            let containerGlobalOrigin = geometry.frame(in: .global).origin
            let headerPane = focusedPane ?? columns.first?.panes.first
            let firstPaneHeaderFrames = headerPane.flatMap {
                paneHeaderFrames[$0.id]
            }
            let topLeftPaneHeaderFrames = columns.first?.panes.first.flatMap {
                paneHeaderFrames[$0.id]
            }
            let toggleCenter = SplitContainerLayout.sidebarToggleCenter(
                for: topLeftPaneHeaderFrames,
                containerGlobalOrigin: containerGlobalOrigin,
                isSidebarShowing: isShowingNoteSidebar
            )

            ZStack(alignment: .topLeading) {
                paneGrid(
                    columns: columns,
                    panes: panes,
                    previewTarget: previewTarget,
                    committedGrid: committedGrid,
                    previewGrid: previewGrid,
                    columnWidths: committedColumnWidths,
                    rowHeights: committedRowHeights,
                    containerSize: geometry.size
                )

                if previewGrid.columns.count > 1 {
                    ForEach(
                        0..<(previewGrid.columns.count - 1),
                        id: \.self
                    ) { dividerIndex in
                        ColumnDividerView(
                            app: app,
                            dividerIndex: dividerIndex,
                            containerWidth: geometry.size.width
                        )
                        .frame(height: geometry.size.height)
                        .position(
                            x: previewColumnWidths
                                .prefix(dividerIndex + 1)
                                .reduce(0, +),
                            y: geometry.size.height / 2
                        )
                    }
                }

                ForEach(
                    Array(previewGrid.columns.enumerated()),
                    id: \.offset
                ) { columnEntry in
                    let columnIndex = columnEntry.offset
                    let column = columnEntry.element

                    if column.rowFractions.count > 1 {
                        ForEach(
                            0..<(column.rowFractions.count - 1),
                            id: \.self
                        ) { dividerIndex in
                            RowDividerView(
                                app: app,
                                columnIndex: columnIndex,
                                dividerIndex: dividerIndex,
                                containerHeight: geometry.size.height
                            )
                            .frame(width: previewColumnWidths[columnIndex])
                            .position(
                                x: previewColumnWidths.prefix(columnIndex).reduce(0, +)
                                    + previewColumnWidths[columnIndex] / 2,
                                y: previewRowHeights[columnIndex]
                                    .prefix(dividerIndex + 1)
                                    .reduce(0, +)
                            )
                        }
                    }
                }

                DockableToolbarContainer(
                    store: app.toolPreferences,
                    containerSize: geometry.size,
                    topObstructions: SplitContainerLayout.topDockObstructions(
                        for: firstPaneHeaderFrames,
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
                        isShowingPaperOptions: Binding(
                            get: { app.split.isShowingPaperOptions },
                            set: { app.split.isShowingPaperOptions = $0 }
                        ),
                        canvasReference: focusedPane?.canvasReference
                            ?? fallbackCanvasReference,
                        backgroundStyle: focusedPane.map { pane in
                            Binding(
                                get: { pane.noteModel.backgroundStyle },
                                set: { pane.noteModel.backgroundStyle = $0 }
                            )
                        },
                        pageOrientation: app.split.focusedPane?
                            .noteModel.note?.pageOrientation ?? .portrait,
                        isPageOrientationAvailable: app.split.focusedPane?
                            .noteModel.pdfBands.isEmpty ?? false,
                        onSetPageOrientation: { orientation in
                            _ = app.split.focusedPane?
                                .noteModel.setPageOrientation(orientation)
                        },
                        orientationWouldPushContentOffPage: { orientation in
                            app.split.focusedPane?.noteModel
                                .orientationWouldPushContentOffPage(to: orientation) ?? false
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

                EdgeSwipeDetector(isEnabled: !isShowingNoteSidebar) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isShowingNoteSidebar = true
                    }
                }
                .frame(width: 20, height: geometry.size.height)
                .zIndex(5)

                noteSidebarToggle
                    .position(toggleCenter)
                    .animation(
                        .easeOut(duration: 0.2),
                        value: isShowingNoteSidebar
                    )
                    .animation(.easeOut(duration: 0.2), value: toggleCenter)
                    .zIndex(9)

                if let ghost {
                    PaneGhostView(
                        title: ghost.title,
                        spaceColor: ghost.spaceColor,
                        intent: ghost.intent
                    )
                    .frame(width: ghost.frame.width, height: ghost.frame.height)
                    .position(x: ghost.frame.midX, y: ghost.frame.midY)
                    .zIndex(6)
                }

                if isShowingNoteSidebar {
                    noteSidebarOverlay(containerSize: geometry.size)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(8)
                }

                if lift != nil {
                    FloatingDragCardView(
                        session: dragSession,
                        commitFrame: ghost?.frame
                    )
                    .zIndex(10)
                }

                Color.clear
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("vellum-split-state")
                    .accessibilityValue(
                        // Short, high-signal fields first. The accessibility value is
                        // length-limited, and the two grid strings are long enough that
                        // trailing fields were being truncated away entirely -- which
                        // read as "the drag never resolved a target" rather than as a
                        // readout problem.
                        "panes:\(panes.count);"
                            + "columns:\(columns.count);"
                            + "focused:\(SplitStateReadout.paneIndex(focusedPaneIndex));"
                            + "orientation:\(app.split.focusedPane?.noteModel.note?.pageOrientation.rawValue ?? "none");"
                            + "dragging:\(lift == nil ? 0 : 1);"
                            + "target:\(SplitStateReadout.dragTarget(resolution));"
                            + "size:\(Int(geometry.size.width.rounded()))x\(Int(geometry.size.height.rounded()));"
                            + "grid:\(SplitStateReadout.grid(committedGrid));"
                            + "preview:\(SplitStateReadout.grid(previewGrid))"
                    )
            }
            .coordinateSpace(name: "splitContainer")
            .onPreferenceChange(PaneHeaderFramesKey.self) {
                paneHeaderFrames = $0
            }
            .onChange(of: geometry.size, initial: true) { _, newSize in
                app.handleSplitContainerResize(newSize)
            }
            .onChange(of: panes.count) {
                app.reclampSplitGrid()
            }
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

    /// Every open note, laid out at its committed size. During a drag each pane
    /// is scaled and offset toward the slot the preview grid gives it, so the
    /// panes animate into the split before the drop commits.
    @ViewBuilder
    private func paneGrid(
        columns: [SplitColumn],
        panes: [NotePane],
        previewTarget: SplitGridDropTarget?,
        committedGrid: SplitGridSnapshot,
        previewGrid: SplitGridSnapshot,
        columnWidths: [CGFloat],
        rowHeights: [[CGFloat]],
        containerSize: CGSize
    ) -> some View {
        if panes.isEmpty {
            ProgressView("Loading note…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                ForEach(
                    Array(columns.enumerated()),
                    id: \.element.id
                ) { columnEntry in
                    let columnIndex = columnEntry.offset
                    let column = columnEntry.element

                    VStack(spacing: 0) {
                        ForEach(
                            Array(column.panes.enumerated()),
                            id: \.element.id
                        ) { paneEntry in
                            let rowIndex = paneEntry.offset
                            let pane = paneEntry.element
                            let paneID = pane.id
                            let paneIndex = PaneIndex(
                                column: columnIndex,
                                row: rowIndex
                            )
                            let transform = SplitContainerLayout.panePreviewTransform(
                                at: paneIndex,
                                target: previewTarget,
                                committedGrid: committedGrid,
                                previewGrid: previewGrid,
                                containerSize: containerSize
                            )

                            NoteScreenView(
                                model: pane.noteModel,
                                app: app,
                                paneContext: PaneContext(
                                    pane: pane,
                                    isFocused: app.split.focusedPaneID == paneID,
                                    paneSize: CGSize(
                                        width: columnWidths[columnIndex],
                                        height: rowHeights[columnIndex][rowIndex]
                                    ),
                                    paneCount: panes.count,
                                    canvasGeneration: pane.canvasGeneration
                                )
                            )
                            .frame(
                                width: columnWidths[columnIndex],
                                height: rowHeights[columnIndex][rowIndex]
                            )
                            .clipped()
                            .geometryGroup()
                            .scaleEffect(
                                x: transform.scale.width,
                                y: transform.scale.height,
                                anchor: .topLeading
                            )
                            .offset(transform.offset)
                        }
                    }
                    .frame(
                        width: columnWidths[columnIndex],
                        height: containerSize.height,
                        alignment: .top
                    )
                }
            }
            .frame(
                width: containerSize.width,
                height: containerSize.height,
                alignment: .leading
            )
        }
    }

    private var noteSidebarToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                isShowingNoteSidebar.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VellumTheme.accentDark)
                .frame(width: 44, height: 44)
                .background(
                    VellumTheme.popover,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(VellumTheme.ink(0.12), lineWidth: 1)
                }
                .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
                .contentShape(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .geometryGroup()
        .accessibilityLabel("Show notes sidebar")
    }

    private func noteSidebarOverlay(containerSize: CGSize) -> some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissNoteSidebar()
                }

            NoteSplitSidebarView(
                app: app,
                containerWidth: containerSize.width,
                onDismiss: dismissNoteSidebar,
                onDragPrepare: {
                    dragHaptics.prepare()
                },
                onDragBegan: { summary, spaceColor, location in
                    beginSidebarDrag(
                        noteID: summary.id,
                        title: summary.title.isEmpty ? "Untitled" : summary.title,
                        spaceColor: spaceColor,
                        location: location,
                        containerSize: containerSize
                    )
                },
                onDragMoved: { location in
                    moveSidebarDrag(
                        to: location,
                        containerSize: containerSize
                    )
                },
                onDragEnded: {
                    endSidebarDrag(containerSize: containerSize)
                },
                onDragCancelled: cancelSidebarDrag
            )
            .frame(width: SplitContainerLayout.sidebarWidth)
            .padding(SplitContainerLayout.sidebarOuterPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func beginSidebarDrag(
        noteID: UUID,
        title: String,
        spaceColor: Color?,
        location: CGPoint,
        containerSize: CGSize
    ) {
        let drop = sidebarDropResolution(
            for: noteID,
            at: location,
            containerSize: containerSize,
            holding: nil
        )
        let dragID = UUID()
        dragSession.lift = SplitDragLift(
            dragID: dragID,
            noteID: noteID,
            title: title,
            spaceColor: spaceColor,
            grabOffset: .zero
        )
        dragSession.location = location
        dragSession.originLocation = location
        dragSession.resolution = drop.resolution
        dragSession.refusedTarget = drop.refusedTarget
        dragSession.isLifted = false
        dragSession.isCommitting = false
        dragHaptics.liftOccurred()
        if drop.resolution != .cancelZone {
            dragHaptics.selectionChanged()
        }

        Task { @MainActor in
            guard dragSession.lift?.dragID == dragID else { return }
            dragSession.isLifted = true
        }
    }

    private func moveSidebarDrag(
        to location: CGPoint,
        containerSize: CGSize
    ) {
        guard let lift = dragSession.lift,
              !dragSession.isCommitting else {
            return
        }

        // Finger tracking is deliberately outside the target animation. Only
        // this lightweight leaf observation should update at display cadence.
        dragSession.location = location

        let drop = sidebarDropResolution(
            for: lift.noteID,
            at: location,
            containerSize: containerSize,
            holding: dragSession.resolution?.target ?? dragSession.refusedTarget
        )
        guard drop.resolution != dragSession.resolution
                || drop.refusedTarget != dragSession.refusedTarget else {
            return
        }

        dragHaptics.selectionChanged()
        withAnimation(dropAnimation) {
            dragSession.resolution = drop.resolution
            dragSession.refusedTarget = drop.refusedTarget
        }
    }

    private func endSidebarDrag(containerSize: CGSize) {
        guard let lift = dragSession.lift,
              !dragSession.isCommitting else {
            return
        }
        let drop = sidebarDropResolution(
            for: lift.noteID,
            at: dragSession.location,
            containerSize: containerSize,
            holding: dragSession.resolution?.target ?? dragSession.refusedTarget
        )
        if drop.resolution != dragSession.resolution
            || drop.refusedTarget != dragSession.refusedTarget {
            dragHaptics.selectionChanged()
            withAnimation(dropAnimation) {
                dragSession.resolution = drop.resolution
                dragSession.refusedTarget = drop.refusedTarget
            }
        }

        switch drop.resolution {
        case .cancelZone:
            resetDragSession()
        case .capacityFull:
            app.showToast("Not enough room for another pane")
            returnDragToOrigin(dragID: lift.dragID)
        case .target(let target):
            commitSidebarDrag(lift: lift, target: target)
        }
    }

    private func cancelSidebarDrag() {
        guard !dragSession.isCommitting else { return }
        resetDragSession()
    }

    private func dismissNoteSidebar() {
        guard !dragSession.isCommitting else { return }
        resetDragSession()
        withAnimation(.easeOut(duration: 0.2)) {
            isShowingNoteSidebar = false
        }
    }

    private func sidebarDropResolution(
        for noteID: UUID,
        at location: CGPoint,
        containerSize: CGSize,
        holding heldTarget: SplitGridDropTarget?
    ) -> (resolution: SidebarDropResolution, refusedTarget: SplitGridDropTarget?) {
        guard location.x > SplitContainerLayout.sidebarCancelZoneMaxX else {
            return (.cancelZone, nil)
        }

        if let existingPane = app.split.pane(for: noteID),
           let existingPaneIndex = app.split.paneIndex(of: existingPane.id) {
            return (.target(.existingPane(existingPaneIndex)), nil)
        }

        let committedGrid = app.split.gridSnapshot
        if let target = SplitGridPolicy.feasibleDropTarget(
            at: location,
            grid: committedGrid,
            containerSize: containerSize,
            holding: heldTarget
        ) {
            return (.target(target), nil)
        }

        let refusedTarget = SplitGridPolicy.dropTarget(
            at: location,
            grid: committedGrid,
            containerSize: containerSize,
            holding: heldTarget
        )
        return (.capacityFull, refusedTarget)
    }

    private var dropAnimation: Animation {
        .spring(response: 0.3, dampingFraction: 0.75)
    }

    private func commitSidebarDrag(
        lift: SplitDragLift,
        target: SplitGridDropTarget
    ) {
        withAnimation(dropAnimation) {
            dragSession.isCommitting = true
        }

        Task { @MainActor in
            // Let SwiftUI present the card-to-ghost transition before note IO
            // completes and swaps the preview grid for the committed grid.
            await Task.yield()

            let openedPaneID: UUID?
            switch target {
            case .existingPane:
                // Focus-only: this target exists precisely because the note is already
                // open. Routing it through openNote's replaceFocused fallback would
                // re-introduce replace-by-drop if the pane closes mid-drag.
                if let pane = app.split.pane(for: lift.noteID) {
                    app.split.focus(pane.id)
                    openedPaneID = pane.id
                } else {
                    openedPaneID = nil
                }
            case .insertColumn(let index):
                openedPaneID = await app.openNote(
                    lift.noteID,
                    placement: .newColumn(at: index)
                )
            case .insertRow(let column, let row):
                openedPaneID = await app.openNote(
                    lift.noteID,
                    placement: .stackInColumn(column: column, at: row)
                )
            }

            guard dragSession.lift?.dragID == lift.dragID else { return }
            guard openedPaneID != nil else {
                returnDragToOrigin(dragID: lift.dragID)
                return
            }

            dragHaptics.dropOccurred()
            resetDragSession()
            withAnimation(.easeOut(duration: 0.2)) {
                isShowingNoteSidebar = false
            }
        }
    }

    private func returnDragToOrigin(dragID: UUID) {
        withAnimation(
            dropAnimation,
            completionCriteria: .logicallyComplete
        ) {
            dragSession.location = dragSession.originLocation
            dragSession.resolution = nil
            dragSession.refusedTarget = nil
            dragSession.isCommitting = false
        } completion: {
            guard dragSession.lift?.dragID == dragID else { return }
            resetDragSession()
        }
    }

    private func resetDragSession() {
        dragSession.lift = nil
        dragSession.location = .zero
        dragSession.resolution = nil
        dragSession.isLifted = false
        dragSession.isCommitting = false
        dragSession.refusedTarget = nil
        dragSession.originLocation = .zero
    }
}
