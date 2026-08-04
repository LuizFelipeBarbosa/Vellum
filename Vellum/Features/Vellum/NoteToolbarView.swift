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
        Rectangle()
            .fill(VellumTheme.ink(0.12))
            .frame(
                width: isVertical ? 1 : nil,
                height: isVertical ? nil : 1
            )
    }

    private var toolsSection: some View {
        let stack = isVertical
            ? AnyLayout(VStackLayout(spacing: 14))
            : AnyLayout(HStackLayout(spacing: 14))
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
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("Paper options")
            }

            collapseButton
        }
        .padding(.horizontal, isVertical ? 10 : 22)
        .padding(.vertical, isVertical ? 22 : 10)
    }

    private var collapsedToolbar: some View {
        let stack = isVertical
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return stack {
            Image(systemName: systemImage(for: selectedTool))
                .frame(width: 24, height: 24)
                .foregroundStyle(VellumTheme.accentDark)
                .accessibilityHidden(true)

            collapseButton
        }
        .padding(.horizontal, isVertical ? 10 : 14)
        .padding(.vertical, isVertical ? 14 : 10)
    }

    private var itemDivider: some View {
        Rectangle()
            .fill(VellumTheme.ink(0.12))
            .frame(
                width: isVertical ? 20 : 1,
                height: isVertical ? 1 : 20
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
                .frame(width: 24, height: 24)
                .foregroundStyle(
                    selectedTool == tool
                        ? VellumTheme.accentDark
                        : tool == .highlighter
                            ? VellumTheme.toolbarMarker
                            : VellumTheme.mutedDark
                )
                .background(
                    selectedTool == tool ? VellumTheme.accent(0.11) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
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
        if isVertical {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
        } else {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .frame(width: 24, height: 20)
                Text(title)
                    .font(captionFont)
                    .lineLimit(1)
            }
            .frame(minWidth: 32)
        }
    }

    private func quietActionLabel(systemImage: String) -> some View {
        let shape = OrganicPillShape(variant: 3, smallRadius: 8)
        return Image(systemName: systemImage)
            .frame(width: 24, height: 24)
            .padding(3)
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
