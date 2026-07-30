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
    case target(SplitGridDropTarget)
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
            let columns = app.split.columns
            let panes = app.split.panes
            let focusedPane = app.split.focusedPane
            let grid = app.split.gridSnapshot
            let columnWidths = SplitGridPolicy.columnWidths(
                grid: grid,
                containerWidth: geometry.size.width
            )
            let rowHeights = grid.columns.map {
                SplitGridPolicy.rowHeights(
                    column: $0,
                    containerHeight: geometry.size.height
                )
            }
            let focusedPaneIndex = app.split.focusedPaneID.flatMap {
                app.split.paneIndex(of: $0)
            }
            let containerGlobalOrigin = geometry.frame(in: .global).origin
            let headerPane = focusedPaneIndex.flatMap { index in
                columns.indices.contains(index.column)
                    ? columns[index.column].panes.first
                    : nil
            } ?? columns.first?.panes.first
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
                                    let appModel = app

                                    NoteScreenView(
                                        model: pane.noteModel,
                                        app: appModel,
                                        paneContext: PaneContext(
                                            pane: pane,
                                            isFocused: app.split.focusedPaneID == paneID,
                                            paneWidth: columnWidths[columnIndex],
                                            paneHeight: rowHeights[columnIndex][rowIndex],
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
                                    .frame(
                                        width: columnWidths[columnIndex],
                                        height: rowHeights[columnIndex][rowIndex]
                                    )
                                    .clipped()
                                }
                            }
                            .frame(
                                width: columnWidths[columnIndex],
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

                if columns.count > 1 {
                    ForEach(0..<(columns.count - 1), id: \.self) { dividerIndex in
                        ColumnDividerView(
                            app: app,
                            dividerIndex: dividerIndex,
                            containerWidth: geometry.size.width
                        )
                        .frame(height: geometry.size.height)
                        .position(
                            x: columnWidths
                                .prefix(dividerIndex + 1)
                                .reduce(0, +),
                            y: geometry.size.height / 2
                        )
                    }
                }

                ForEach(
                    Array(columns.enumerated()),
                    id: \.element.id
                ) { columnEntry in
                    let columnIndex = columnEntry.offset
                    let column = columnEntry.element

                    if column.panes.count > 1 {
                        ForEach(
                            0..<(column.panes.count - 1),
                            id: \.self
                        ) { dividerIndex in
                            RowDividerView(
                                app: app,
                                columnIndex: columnIndex,
                                dividerIndex: dividerIndex,
                                containerHeight: geometry.size.height
                            )
                            .frame(width: columnWidths[columnIndex])
                            .position(
                                x: columnWidths.prefix(columnIndex).reduce(0, +)
                                    + columnWidths[columnIndex] / 2,
                                y: rowHeights[columnIndex]
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

                dragDropIndicator(
                    columnWidths: columnWidths,
                    containerSize: geometry.size
                )
                .zIndex(6)

                if isShowingNoteSidebar {
                    noteSidebarOverlay(containerSize: geometry.size)
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
                            + "columns:\(columns.count);"
                            + "grid:\(formattedGrid(grid));"
                            + "focused:\(formattedPaneIndex(focusedPaneIndex));"
                            + "dragging:\(dragState == nil ? 0 : 1);"
                            + "target:\(formattedDragTarget(dragState));"
                            + "size:\(Int(geometry.size.width.rounded()))x\(Int(geometry.size.height.rounded()))"
                    )
            }
            .coordinateSpace(name: "splitContainer")
            .onPreferenceChange(PaneHeaderFramesKey.self) {
                paneHeaderFrames = $0
            }
            .onChange(of: geometry.size, initial: true) { _, newSize in
                app.handleSplitContainerResize(newSize)
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

    @ViewBuilder
    private func dragDropIndicator(
        columnWidths: [CGFloat],
        containerSize: CGSize
    ) -> some View {
        switch dragState?.target {
        case .insertColumn(let index):
            Rectangle()
                .fill(VellumTheme.accent)
                .frame(width: 3, height: containerSize.height)
                .position(
                    x: insertionBoundaryX(
                        at: index,
                        columnWidths: columnWidths
                    ),
                    y: containerSize.height / 2
                )
                .allowsHitTesting(false)
        case .insertRow(let column, let row):
            if columnWidths.indices.contains(column),
               app.split.gridSnapshot.columns.indices.contains(column) {
                let rowHeights = SplitGridPolicy.rowHeights(
                    column: app.split.gridSnapshot.columns[column],
                    containerHeight: containerSize.height
                )
                if row >= 0, row <= rowHeights.count {
                    let columnX = columnWidths.prefix(column).reduce(0, +)
                    Rectangle()
                        .fill(VellumTheme.accent)
                        .frame(width: columnWidths[column], height: 3)
                        .position(
                            x: columnX + columnWidths[column] / 2,
                            y: rowHeights.prefix(row).reduce(0, +)
                        )
                        .allowsHitTesting(false)
                } else {
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        case .existingPane(let paneIndex):
            if let rect = SplitGridPolicy.paneFrame(
                at: paneIndex,
                grid: app.split.gridSnapshot,
                containerSize: containerSize
            ) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(VellumTheme.accent(0.55), lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            } else {
                EmptyView()
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
        containerSize: CGSize
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
                containerSize: containerSize
            ).target
        )
    }

    private func moveSidebarDrag(
        to location: CGPoint,
        containerSize: CGSize
    ) {
        guard var state = dragState else { return }
        state.location = location
        state.target = sidebarDropResolution(
            for: state.noteID,
            at: location,
            containerSize: containerSize
        ).target
        dragState = state
    }

    private func endSidebarDrag(containerSize: CGSize) {
        guard let state = dragState else { return }
        let resolution = sidebarDropResolution(
            for: state.noteID,
            at: state.location,
            containerSize: containerSize
        )

        switch resolution {
        case .cancelZone:
            dragState = nil
        case .capacityFull:
            dragState = nil
            app.showToast("Not enough room for another pane")
        case .target(.existingPane(let paneIndex)):
            if let pane = app.split.pane(for: state.noteID) {
                dragState = nil
                app.split.focus(pane.id)
            } else {
                guard app.split.columns.indices.contains(paneIndex.column),
                      app.split.columns[paneIndex.column].panes.indices
                        .contains(paneIndex.row) else {
                    dragState = nil
                    return
                }
                let pane = app.split.columns[paneIndex.column].panes[paneIndex.row]
                let noteID = state.noteID
                dragState = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    isShowingNoteSidebar = false
                }
                Task {
                    await app.openNote(
                        noteID,
                        placement: .replacePane(id: pane.id)
                    )
                }
            }
        case .target(.insertColumn(let index)):
            let noteID = state.noteID
            dragState = nil
            withAnimation(.easeOut(duration: 0.2)) {
                isShowingNoteSidebar = false
            }
            Task {
                await app.openNote(
                    noteID,
                    placement: .newColumn(at: index)
                )
            }
        case .target(.insertRow(let column, let row)):
            let noteID = state.noteID
            dragState = nil
            withAnimation(.easeOut(duration: 0.2)) {
                isShowingNoteSidebar = false
            }
            Task {
                await app.openNote(
                    noteID,
                    placement: .stackInColumn(
                        column: column,
                        at: row
                    )
                )
            }
        }
    }

    private func cancelSidebarDrag() {
        dragState = nil
    }

    private func dismissNoteSidebar() {
        dragState = nil
        withAnimation(.easeOut(duration: 0.2)) {
            isShowingNoteSidebar = false
        }
    }

    private func sidebarDropResolution(
        for noteID: UUID,
        at location: CGPoint,
        containerSize: CGSize
    ) -> SidebarDropResolution {
        guard location.x > noteSidebarCancelZoneMaxX else {
            return .cancelZone
        }

        if let existingPane = app.split.pane(for: noteID),
           let existingPaneIndex = app.split.paneIndex(of: existingPane.id) {
            return .target(.existingPane(existingPaneIndex))
        }

        let grid = app.split.gridSnapshot
        let target = SplitGridPolicy.dropTarget(
            at: location,
            grid: grid,
            containerSize: containerSize
        )

        switch target {
        case .existingPane:
            return .target(target)
        case .insertColumn, .insertRow:
            guard SplitGridPolicy.allows(
                target,
                grid: grid,
                containerSize: containerSize
            ) else {
                return .capacityFull
            }
            return .target(target)
        }
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
        columnWidths: [CGFloat]
    ) -> CGFloat {
        columnWidths
            .prefix(min(max(index, 0), columnWidths.count))
            .reduce(0, +)
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
        grid.columns.map { column in
            let width = formattedFraction(column.widthFraction)
            let rows = column.rowFractions
                .map { formattedFraction($0) }
                .joined(separator: ",")
            return "\(width)[\(rows)]"
        }
        .joined(separator: "|")
    }

    private func formattedPaneIndex(_ index: PaneIndex?) -> String {
        guard let index else { return "-1" }
        return "\(index.column).\(index.row)"
    }

    private func formattedDragTarget(_ state: SplitDragState?) -> String {
        switch state?.target {
        case .insertColumn(let index):
            "col-\(index)"
        case .insertRow(let column, let row):
            "row-\(column).\(row)"
        case .existingPane(let paneIndex):
            "pane-\(paneIndex.column).\(paneIndex.row)"
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
