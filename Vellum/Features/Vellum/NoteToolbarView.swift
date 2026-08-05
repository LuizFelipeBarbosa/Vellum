import PencilKit
import SwiftUI
import VellumCore

@MainActor
final class NoteCanvasReference {
    weak var canvasView: PKCanvasView?

    var coordinator: PencilCanvasView.Coordinator? {
        canvasView?.delegate as? PencilCanvasView.Coordinator
    }
}

struct NoteToolbarView: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let store: ToolPreferencesStore
    @Binding var selectedTool: ToolID
    @Binding var activeOptionsTool: ToolID?
    @Binding var isShowingPaperOptions: Bool
    @State private var isShowingFavoritesEditor = false
    let canvasReference: NoteCanvasReference
    var backgroundStyle: Binding<PageBackgroundStyle>? = nil
    var pageOrientation: PageOrientation = .portrait
    var isPageOrientationAvailable: Bool = false
    var onSetPageOrientation: ((PageOrientation) -> Void)? = nil
    var orientationWouldPushContentOffPage: ((PageOrientation) -> Bool)? = nil
    var onInsertPhoto: (() -> Void)? = nil
    var onInsertFile: (() -> Void)? = nil
    var dockEdge: ToolbarDockEdge = .bottom
    var availableAxisLength: CGFloat? = nil

    private var isVertical: Bool { dockEdge.axis == .vertical }

    private var arrowEdge: Edge {
        switch dockEdge {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    var body: some View {
        Group {
            if store.preferences.isToolbarCollapsed {
                collapsedToolbar
            } else {
                expandedToolbar
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(VellumTheme.mutedDark)
        .vellumFloatingChrome(.pill(variant: 1))
        .popover(item: $activeOptionsTool, arrowEdge: arrowEdge) { tool in
            ToolOptionsPopover(tool: tool, store: store)
        }
        .popover(isPresented: $isShowingFavoritesEditor, arrowEdge: arrowEdge) {
            FavoritesEditView(store: store)
        }
        .popover(isPresented: $isShowingPaperOptions, arrowEdge: arrowEdge) {
            if let backgroundStyle {
                PageBackgroundOptionsView(
                    style: backgroundStyle,
                    pageOrientation: pageOrientation,
                    isPageOrientationAvailable: isPageOrientationAvailable,
                    onSetPageOrientation: onSetPageOrientation,
                    orientationWouldPushContentOffPage: orientationWouldPushContentOffPage
                )
            }
        }
    }

    private var expandedToolbar: some View {
        let sectionStack = isVertical
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        return sectionStack {
            if dockEdge.secondarySectionLeads {
                secondarySection
                if hasSecondarySection {
                    sectionDivider
                }
                toolsSection
            } else {
                toolsSection
                if hasSecondarySection {
                    sectionDivider
                }
                secondarySection
            }
        }
    }

    private var hasSecondarySection: Bool { selectedTool != .text }

    @ViewBuilder
    private var secondarySection: some View {
        switch selectedTool {
        case .pen, .pencil, .highlighter:
            FavoriteColorRow(
                store: store,
                activeInkTool: selectedTool,
                axis: dockEdge.axis,
                availableLength: availableAxisLength,
                onRequestOptions: {
                    activeOptionsTool = selectedTool
                },
                onRequestFavoritesEditor: {
                    isShowingFavoritesEditor = true
                }
            )
        case .eraser:
            EraserModeRow(store: store, axis: dockEdge.axis)
        case .select:
            SelectionModeRow(store: store, axis: dockEdge.axis)
        case .text:
            EmptyView()
        }
    }

    private var sectionDivider: some View {
        VellumDashedRule(axis: isVertical ? .vertical : .horizontal)
            .stroke(
                VellumTheme.ink(0.2),
                style: StrokeStyle(lineWidth: 1, dash: [3, 4])
            )
            .frame(
                width: isVertical ? ToolbarMetrics.dividerThickness : nil,
                height: isVertical ? nil : ToolbarMetrics.dividerThickness
            )
    }

    private var toolsSection: some View {
        let stack = isVertical
            ? AnyLayout(VStackLayout(spacing: ToolbarMetrics.itemSpacing))
            : AnyLayout(HStackLayout(spacing: ToolbarMetrics.itemSpacing))
        return stack {
            Button {
                canvasReference.canvasView?.undoManager?.undo()
            } label: {
                toolbarItemLabel(
                    systemImage: "arrow.uturn.backward",
                    title: "Undo",
                    captionFont: .vellumMono(9)
                )
            }
            .accessibilityLabel("Undo")

            Button {
                canvasReference.canvasView?.undoManager?.redo()
            } label: {
                toolbarItemLabel(
                    systemImage: "arrow.uturn.forward",
                    title: "Redo",
                    captionFont: .vellumMono(9)
                )
            }
            .accessibilityLabel("Redo")

            itemDivider

            toolButton(.pen, systemImage: "pencil.tip")
            toolButton(.pencil, systemImage: "pencil")
            toolButton(.highlighter, systemImage: "highlighter")
            toolButton(.eraser, systemImage: "eraser")
            toolButton(.select, systemImage: "lasso")
            toolButton(.text, systemImage: "character.cursor.ibeam")

            itemDivider

            Menu {
                Button {
                    onInsertPhoto?()
                } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }
                .disabled(onInsertPhoto == nil)

                Button {
                    onInsertFile?()
                } label: {
                    Label("Files", systemImage: "folder")
                }
                .disabled(onInsertFile == nil)
            } label: {
                quietActionLabel(systemImage: "plus.circle")
            }
            .accessibilityLabel("Insert")

            if backgroundStyle != nil {
                Button {
                    isShowingPaperOptions.toggle()
                } label: {
                    Image(systemName: "doc.text.image")
                        .frame(
                            width: ToolbarMetrics.itemHitSize,
                            height: ToolbarMetrics.itemHitSize
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Paper options")
            }

            collapseButton
                .padding(
                    isVertical ? .bottom : .trailing,
                    ToolbarMetrics.collapseCornerClearance
                )
        }
        .padding(
            .horizontal,
            isVertical ? ToolbarMetrics.crossPadding : ToolbarMetrics.endPadding
        )
        .padding(
            .vertical,
            isVertical ? ToolbarMetrics.endPadding : ToolbarMetrics.crossPadding
        )
    }

    private var collapsedToolbar: some View {
        let stack = isVertical
            ? AnyLayout(VStackLayout(spacing: ToolbarMetrics.collapsedSpacing))
            : AnyLayout(HStackLayout(spacing: ToolbarMetrics.collapsedSpacing))
        return stack {
            Image(systemName: systemImage(for: selectedTool))
                .frame(
                    width: ToolbarMetrics.itemHitSize,
                    height: ToolbarMetrics.itemHitSize
                )
                .foregroundStyle(VellumTheme.accentDark)
                .accessibilityHidden(true)

            collapseButton
                .padding(
                    isVertical ? .bottom : .trailing,
                    ToolbarMetrics.collapseCornerClearance
                )
        }
        .padding(
            .horizontal,
            isVertical ? ToolbarMetrics.crossPadding : ToolbarMetrics.collapsedEndPadding
        )
        .padding(
            .vertical,
            isVertical ? ToolbarMetrics.collapsedEndPadding : ToolbarMetrics.crossPadding
        )
    }

    private var itemDivider: some View {
        VellumDashedRule(axis: isVertical ? .horizontal : .vertical)
            .stroke(
                VellumTheme.ink(0.2),
                style: StrokeStyle(lineWidth: 1, dash: [3, 4])
            )
            .frame(
                width: isVertical
                    ? ToolbarMetrics.dividerLength
                    : ToolbarMetrics.dividerThickness,
                height: isVertical
                    ? ToolbarMetrics.dividerThickness
                    : ToolbarMetrics.dividerLength
            )
    }

    private func toolButton(
        _ tool: ToolID,
        systemImage: String
    ) -> some View {
        Button {
            if selectedTool == tool {
                if tool != .select {
                    activeOptionsTool = tool
                }
            } else {
                selectedTool = tool
            }
        } label: {
            Image(systemName: systemImage)
                .frame(
                    width: ToolbarMetrics.itemHitSize,
                    height: ToolbarMetrics.itemHitSize
                )
                .foregroundStyle(
                    selectedTool == tool
                        ? VellumTheme.accentDark
                        : tool == .highlighter
                            ? VellumTheme.toolbarMarker
                            : VellumTheme.mutedDark
                )
                .contentShape(Rectangle())
                .background(
                    selectedTool == tool ? VellumTheme.accent(0.11) : .clear,
                    in: OrganicPillShape(
                        variant: 1,
                        smallRadius: ToolbarMetrics.selectedPillRadius,
                        isOrganic: vellumWobble
                    )
                )
        }
        .accessibilityLabel(tool.displayName)
        .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                store.update { preferences in
                    preferences.isToolbarCollapsed.toggle()
                }
            }
        } label: {
            quietActionLabel(systemImage: collapseSystemImage)
        }
        .accessibilityLabel(
            store.preferences.isToolbarCollapsed ? "Expand toolbar" : "Collapse toolbar"
        )
    }

    private var collapseSystemImage: String {
        switch dockEdge {
        case .bottom:
            store.preferences.isToolbarCollapsed ? "chevron.up" : "chevron.down"
        case .top:
            store.preferences.isToolbarCollapsed ? "chevron.down" : "chevron.up"
        case .left:
            store.preferences.isToolbarCollapsed ? "chevron.right" : "chevron.left"
        case .right:
            store.preferences.isToolbarCollapsed ? "chevron.left" : "chevron.right"
        }
    }

    @ViewBuilder
    private func toolbarItemLabel(
        systemImage: String,
        title: String,
        captionFont: Font
    ) -> some View {
        VStack(spacing: ToolbarMetrics.captionSpacing) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 22)
            Text(title)
                .font(captionFont)
                .lineLimit(1)
        }
        .frame(
            minWidth: ToolbarMetrics.captionedItemMinWidth,
            minHeight: ToolbarMetrics.itemHitSize
        )
    }

    private func quietActionLabel(systemImage: String) -> some View {
        let shape = OrganicPillShape(variant: 3, smallRadius: 8, isOrganic: vellumWobble)
        return Image(systemName: systemImage)
            .frame(
                width: ToolbarMetrics.quietIconFrame,
                height: ToolbarMetrics.quietIconFrame
            )
            .padding(ToolbarMetrics.quietPadding)
            .background(VellumTheme.paper(0.45), in: shape)
            .overlay {
                shape.strokeBorder(VellumTheme.ink(0.18), lineWidth: 1)
            }
    }

    private func systemImage(for tool: ToolID) -> String {
        switch tool {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .select: "lasso"
        case .text: "character.cursor.ibeam"
        }
    }
}
