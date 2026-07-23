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
    @State private var isShowingFavoritesEditor = false
    @State private var isShowingBackgroundOptions = false
    let canvasReference: NoteCanvasReference
    var backgroundStyle: Binding<PageBackgroundStyle>? = nil
    var onInsertPhoto: (() -> Void)? = nil
    var onInsertFile: (() -> Void)? = nil

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
        .background(
            VellumTheme.popover,
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(VellumTheme.ink(0.12), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
        .popover(item: $activeOptionsTool, arrowEdge: .bottom) { tool in
            ToolOptionsPopover(tool: tool, store: store)
        }
        .popover(isPresented: $isShowingFavoritesEditor, arrowEdge: .bottom) {
            FavoritesEditView(store: store)
        }
        .popover(isPresented: $isShowingBackgroundOptions, arrowEdge: .bottom) {
            if let backgroundStyle {
                PageBackgroundOptionsView(style: backgroundStyle)
            }
        }
    }

    private var expandedToolbar: some View {
        VStack(spacing: 0) {
            toolbarRow

            if selectedTool.isInkTool {
                Rectangle()
                    .fill(VellumTheme.ink(0.12))
                    .frame(height: 1)

                FavoriteColorRow(
                    store: store,
                    activeInkTool: selectedTool,
                    onRequestOptions: {
                        activeOptionsTool = selectedTool
                    },
                    onRequestFavoritesEditor: {
                        isShowingFavoritesEditor = true
                    }
                )
            }
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 14) {
            Button {
                canvasReference.canvasView?.undoManager?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .accessibilityLabel("Undo")

            Button {
                canvasReference.canvasView?.undoManager?.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .accessibilityLabel("Redo")

            divider

            toolButton(.pen, systemImage: "pencil.tip")
            toolButton(.pencil, systemImage: "pencil")
            toolButton(.highlighter, systemImage: "highlighter")
            toolButton(.eraser, systemImage: "eraser")
            toolButton(.select, systemImage: "lasso")
            toolButton(.text, systemImage: "character.cursor.ibeam")

            divider

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
                Image(systemName: "plus.circle")
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("Insert")

            if backgroundStyle != nil {
                Button {
                    isShowingBackgroundOptions.toggle()
                } label: {
                    Image(systemName: "doc.text.image")
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("Paper options")
            }

            collapseButton
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
    }

    private var collapsedToolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage(for: selectedTool))
                .frame(width: 24, height: 24)
                .foregroundStyle(VellumTheme.accentDark)
                .accessibilityHidden(true)

            collapseButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(VellumTheme.ink(0.12))
            .frame(width: 1, height: 20)
    }

    private func toolButton(
        _ tool: ToolID,
        systemImage: String
    ) -> some View {
        Button {
            if selectedTool == tool {
                activeOptionsTool = tool
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
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                store.update { preferences in
                    preferences.isToolbarCollapsed.toggle()
                }
            }
        } label: {
            Image(
                systemName: store.preferences.isToolbarCollapsed
                    ? "chevron.up"
                    : "chevron.down"
            )
            .frame(width: 24, height: 24)
        }
        .accessibilityLabel(
            store.preferences.isToolbarCollapsed ? "Expand toolbar" : "Collapse toolbar"
        )
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
