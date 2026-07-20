import PencilKit
import SwiftUI

enum NoteDrawingTool: Hashable {
    case pen
    case highlighter
    case eraser
    case lasso
}

enum NoteInkColor: Hashable {
    case ink
    case accent
    case thesis

    var color: Color {
        switch self {
        case .ink: VellumTheme.ink
        case .accent: VellumTheme.accent
        case .thesis: VellumTheme.thesis
        }
    }
}

@MainActor
final class NoteCanvasReference {
    weak var canvasView: PKCanvasView?
}

struct NoteToolbarView: View {
    @Binding var selectedTool: NoteDrawingTool
    @Binding var selectedColor: NoteInkColor
    let canvasReference: NoteCanvasReference

    var body: some View {
        HStack(spacing: 18) {
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

            toolButton(.pen, systemImage: "pencil.tip", label: "Pen")
            toolButton(.highlighter, systemImage: "highlighter", label: "Highlighter")
            toolButton(.eraser, systemImage: "eraser", label: "Eraser")
            toolButton(.lasso, systemImage: "lasso", label: "Lasso")

            divider

            colorDot(.ink)
            colorDot(.accent)
            colorDot(.thesis)
        }
        .buttonStyle(.plain)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(VellumTheme.mutedDark)
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(VellumTheme.popover, in: Capsule())
        .overlay(Capsule().stroke(VellumTheme.ink(0.12), lineWidth: 1))
        .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
    }

    private var divider: some View {
        Rectangle()
            .fill(VellumTheme.ink(0.12))
            .frame(width: 1, height: 20)
    }

    private func toolButton(
        _ tool: NoteDrawingTool,
        systemImage: String,
        label: String
    ) -> some View {
        Button {
            selectedTool = tool
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
        .accessibilityLabel(label)
    }

    private func colorDot(_ inkColor: NoteInkColor) -> some View {
        Button {
            selectedColor = inkColor
            selectedTool = .pen
        } label: {
            Circle()
                .fill(inkColor.color)
                .frame(width: 17, height: 17)
                .overlay {
                    Circle()
                        .stroke(
                            selectedColor == inkColor ? VellumTheme.accent : .clear,
                            lineWidth: 2
                        )
                        .padding(-4)
                }
        }
        .accessibilityLabel(colorLabel(for: inkColor))
    }

    private func colorLabel(for color: NoteInkColor) -> String {
        switch color {
        case .ink: "Ink color"
        case .accent: "Bronze color"
        case .thesis: "Green color"
        }
    }
}
