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

    private var noteSidebarWidth: CGFloat { 300 }
    private var noteSidebarOuterPadding: CGFloat { 18 }
    private var noteSidebarCancelZoneMaxX: CGFloat {
        noteSidebarOuterPadding + noteSidebarWidth + noteSidebarOuterPadding
    }

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
            let ghost = paneGhostConfiguration(
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
            let toggleCenter = sidebarToggleCenter(
                for: topLeftPaneHeaderFrames,
                containerGlobalOrigin: containerGlobalOrigin
            )

            ZStack(alignment: .topLeading) {
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
                                    let transform = panePreviewTransform(
                                        at: paneIndex,
                                        target: previewTarget,
                                        committedGrid: committedGrid,
                                        previewGrid: previewGrid,
                                        containerSize: geometry.size
                                    )

                                    NoteScreenView(
                                        model: pane.noteModel,
                                        app: app,
                                        paneContext: PaneContext(
                                            pane: pane,
                                            isFocused: app.split.focusedPaneID == paneID,
                                            paneSize: CGSize(
                                                width: committedColumnWidths[columnIndex],
                                                height: committedRowHeights[columnIndex][rowIndex]
                                            ),
                                            paneCount: panes.count,
                                            canvasGeneration: pane.canvasGeneration
                                        )
                                    )
                                    .frame(
                                        width: committedColumnWidths[columnIndex],
                                        height: committedRowHeights[columnIndex][rowIndex]
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
                                width: committedColumnWidths[columnIndex],
                                height: geometry.size.height,
                                alignment: .top
                            )
                        }
                    }
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .leading
                    )
                }

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
                    topObstructions: topDockObstructions(
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
                            + "focused:\(formattedPaneIndex(focusedPaneIndex));"
                            + "orientation:\(app.split.focusedPane?.noteModel.note?.pageOrientation.rawValue ?? "none");"
                            + "dragging:\(lift == nil ? 0 : 1);"
                            + "target:\(formattedDragTarget(resolution));"
                            + "size:\(Int(geometry.size.width.rounded()))x\(Int(geometry.size.height.rounded()));"
                            + "grid:\(formattedGrid(committedGrid));"
                            + "preview:\(formattedGrid(previewGrid))"
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
            .frame(width: noteSidebarWidth)
            .padding(noteSidebarOuterPadding)
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
        guard location.x > noteSidebarCancelZoneMaxX else {
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

    private func panePreviewTransform(
        at index: PaneIndex,
        target: SplitGridDropTarget?,
        committedGrid: SplitGridSnapshot,
        previewGrid: SplitGridSnapshot,
        containerSize: CGSize
    ) -> PanePreviewTransform {
        guard let target,
              let committedFrame = SplitGridPolicy.paneFrame(
                at: index,
                grid: committedGrid,
                containerSize: containerSize
              ),
              let previewFrame = SplitGridPolicy.paneFrame(
                at: SplitGridPolicy.paneIndexAfterInserting(target, index),
                grid: previewGrid,
                containerSize: containerSize
              ),
              committedFrame.width > 0,
              committedFrame.height > 0 else {
            return .identity
        }

        return PanePreviewTransform(
            scale: CGSize(
                width: previewFrame.width / committedFrame.width,
                height: previewFrame.height / committedFrame.height
            ),
            offset: CGSize(
                width: previewFrame.minX - committedFrame.minX,
                height: previewFrame.minY - committedFrame.minY
            )
        )
    }

    private func paneGhostConfiguration(
        lift: SplitDragLift?,
        resolution: SidebarDropResolution?,
        refusedTarget: SplitGridDropTarget?,
        committedGrid: SplitGridSnapshot,
        previewGrid: SplitGridSnapshot,
        containerSize: CGSize
    ) -> PaneGhostConfiguration? {
        guard let lift else { return nil }

        let frame: CGRect
        let intent: PaneGhostIntent
        switch resolution {
        case .target(.existingPane(let index)):
            guard let existingFrame = SplitGridPolicy.paneFrame(
                at: index,
                grid: committedGrid,
                containerSize: containerSize
            ) else {
                return nil
            }
            frame = existingFrame
            intent = .alreadyOpen

        case .target(let target):
            guard let insertedIndex = SplitGridPolicy.insertedPaneIndex(for: target),
                  let insertedFrame = SplitGridPolicy.paneFrame(
                    at: insertedIndex,
                    grid: previewGrid,
                    containerSize: containerSize
                  ) else {
                return nil
            }
            frame = insertedFrame
            intent = .split

        case .capacityFull:
            // A refusal leaves the panes untransformed, so the ghost has to be
            // framed on the committed grid: the refused insertion's own index
            // belongs to a hypothetical grid this layout never adopts.
            guard let refusedTarget,
                  let refusedIndex = SplitGridPolicy.clampedPaneIndex(
                    for: refusedTarget,
                    in: committedGrid
                  ),
                  let refusedFrame = SplitGridPolicy.paneFrame(
                    at: refusedIndex,
                    grid: committedGrid,
                    containerSize: containerSize
                  ) else {
                return nil
            }
            frame = refusedFrame
            intent = .refused

        case .cancelZone, nil:
            return nil
        }

        return PaneGhostConfiguration(
            title: lift.title,
            spaceColor: lift.spaceColor,
            intent: intent,
            frame: frame
        )
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

    private func formattedGrid(_ grid: SplitGridSnapshot) -> String {
        let encoded = grid.columns.map { column in
            let width = formattedFraction(column.widthFraction)
            let rows = column.rowFractions
                .map { formattedFraction($0) }
                .joined(separator: ",")
            return "\(width)[\(rows)]"
        }
        .joined(separator: "|")
        return encoded.isEmpty ? "none" : encoded
    }

    private func formattedPaneIndex(_ index: PaneIndex?) -> String {
        guard let index else { return "-1" }
        return "\(index.column).\(index.row)"
    }

    private func formattedDragTarget(
        _ resolution: SidebarDropResolution?
    ) -> String {
        switch resolution {
        case .cancelZone:
            "none"
        case .capacityFull:
            "none-capacity"
        case .target(.insertColumn(let index)):
            "col-\(index)"
        case .target(.insertRow(let column, let row)):
            "row-\(column).\(row)"
        case .target(.existingPane(let paneIndex)):
            "focus-\(paneIndex.column).\(paneIndex.row)"
        case nil:
            "none"
        }
    }

    private func formattedFraction(_ fraction: CGFloat) -> String {
        String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(fraction)
        )
    }
}

private struct PanePreviewTransform {
    let scale: CGSize
    let offset: CGSize

    static let identity = PanePreviewTransform(
        scale: CGSize(width: 1, height: 1),
        offset: .zero
    )
}

private struct PaneGhostConfiguration {
    let title: String
    let spaceColor: Color?
    let intent: PaneGhostIntent
    let frame: CGRect
}

/// This leaf is the only drag view that observes location. Keeping that read
/// here prevents the expensive pane container from being invalidated at 120 Hz.
@MainActor
private struct FloatingDragCardView: View {
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

private extension SidebarDropResolution {
    var target: SplitGridDropTarget? {
        if case .target(let target) = self {
            return target
        }
        return nil
    }
}

@MainActor
struct ColumnDividerView: View {
    let app: VellumAppModel
    let dividerIndex: Int
    let containerWidth: CGFloat

    @State private var gridAtDragStart: SplitGridSnapshot?
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
        .frame(width: SplitGridPolicy.dividerHitThickness)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named("splitContainer")
            )
            .onChanged { value in
                let startGrid = gridAtDragStart ?? app.split.gridSnapshot
                if gridAtDragStart == nil {
                    gridAtDragStart = startGrid
                    isDragging = true
                }
                let grid = SplitGridPolicy.resizingColumnDivider(
                    startGrid,
                    dividerIndex: dividerIndex,
                    byTranslation: value.translation.width,
                    containerWidth: containerWidth
                )
                app.split.applyGrid(grid)
            }
            .onEnded { _ in
                gridAtDragStart = nil
                isDragging = false
            }
        )
    }
}

@MainActor
struct RowDividerView: View {
    let app: VellumAppModel
    let columnIndex: Int
    let dividerIndex: Int
    let containerHeight: CGFloat

    @State private var gridAtDragStart: SplitGridSnapshot?
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(VellumTheme.ink(0.09))
                .frame(height: 1)

            RoundedRectangle(cornerRadius: 2)
                .fill(isDragging ? VellumTheme.accent : VellumTheme.ink(0.18))
                .frame(width: 36, height: 4)
        }
        .frame(height: SplitGridPolicy.dividerHitThickness)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named("splitContainer")
            )
            .onChanged { value in
                let startGrid = gridAtDragStart ?? app.split.gridSnapshot
                if gridAtDragStart == nil {
                    gridAtDragStart = startGrid
                    isDragging = true
                }
                let grid = SplitGridPolicy.resizingRowDivider(
                    startGrid,
                    column: columnIndex,
                    dividerIndex: dividerIndex,
                    byTranslation: value.translation.height,
                    containerHeight: containerHeight
                )
                app.split.applyGrid(grid)
            }
            .onEnded { _ in
                gridAtDragStart = nil
                isDragging = false
            }
        )
    }
}
