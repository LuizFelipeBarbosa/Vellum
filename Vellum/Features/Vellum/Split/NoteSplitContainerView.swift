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

@MainActor
struct NoteSplitContainerView: View {
    @Bindable var app: VellumAppModel
    @State private var fallbackCanvasReference = NoteCanvasReference()
    @State private var paneHeaderFrames: [UUID: PaneHeaderFrames] = [:]

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

                Color.clear
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("vellum-split-state")
                    .accessibilityValue(
                        "panes:\(panes.count);"
                            + "fractions:\(formattedFractions(panes));"
                            + "focused:\(focusedPaneIndex)"
                    )
            }
            .coordinateSpace(name: "splitContainer")
            .onPreferenceChange(PaneHeaderFramesKey.self) {
                paneHeaderFrames = $0
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
