import SwiftUI

struct SelectionActionStripView: View {
    let controller: CanvasSelectionController

    @State private var isShowingStylePopover = false
    @State private var styleColor = ToolPreferences.default.pen.color
    @State private var styleWidth = ToolPreferences.default.pen.width

    private static let actionStripSize = CGSize(width: 510, height: 40)

    var body: some View {
        actionStrip
    }

    private var actionStrip: some View {
        HStack(spacing: 4) {
            Button {
                controller.cutSelection()
            } label: {
                actionLabel("Cut", systemImage: "scissors")
            }
            .accessibilityLabel("Cut selection")

            Button {
                controller.copySelection()
            } label: {
                actionLabel("Copy", systemImage: "doc.on.doc")
            }
            .accessibilityLabel("Copy selection")

            Button {
                Task {
                    await controller.pasteFromPasteboard()
                }
            } label: {
                actionLabel("Paste", systemImage: "doc.on.clipboard")
            }
            .disabled(!controller.canPaste)
            .accessibilityLabel("Paste selection")

            Button {
                isShowingStylePopover.toggle()
            } label: {
                actionLabel("Style", systemImage: "paintpalette")
            }
            .accessibilityLabel("Style selection")
            .popover(isPresented: $isShowingStylePopover) {
                stylePopover
            }

            Button {
                controller.duplicateSelection()
            } label: {
                actionLabel("Duplicate", systemImage: "plus.square.on.square")
            }
            .accessibilityLabel("Duplicate selection")

            Button(role: .destructive) {
                controller.deleteSelection()
            } label: {
                actionLabel("Delete", systemImage: "trash")
            }
            .foregroundStyle(.red)
            .accessibilityLabel("Delete selection")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(VellumTheme.mutedDark)
        .frame(width: Self.actionStripSize.width, height: Self.actionStripSize.height)
        .background(VellumTheme.popover, in: Capsule())
        .overlay {
            Capsule().stroke(VellumTheme.ink(0.12), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }

    private var stylePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Selection Style")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)

            ColorSwatchGrid(
                favorites: ToolPreferences.defaultFavorites,
                selectedColor: styleColor,
                onSelect: { color in
                    styleColor = color
                    controller.restyleSelection(color: color, strokeWidth: nil)
                }
            )

            Text("STROKE WIDTH")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VellumTheme.mutedDark)

            HStack(spacing: 12) {
                Slider(value: $styleWidth, in: 1...30) { editing in
                    if !editing {
                        controller.restyleSelection(
                            color: nil,
                            strokeWidth: styleWidth
                        )
                    }
                }
                .accessibilityLabel("Selection stroke width")
                .accessibilityValue("\(Int(styleWidth.rounded())) points")

                Text("\(Int(styleWidth.rounded()))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VellumTheme.mutedDark)
                    .frame(width: 24, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .background(VellumTheme.popover)
    }

    static func position(for viewRect: CGRect, in viewportSize: CGSize) -> CGPoint {
        let margin: CGFloat = 8

        let x: CGFloat
        if viewportSize.width < actionStripSize.width + margin * 2 {
            x = viewportSize.width / 2
        } else {
            x = min(
                max(viewRect.midX, actionStripSize.width / 2 + margin),
                viewportSize.width - actionStripSize.width / 2 - margin
            )
        }

        let desiredY = viewRect.minY - 12 - actionStripSize.height / 2
        let y: CGFloat
        if viewportSize.height < actionStripSize.height + margin * 2 {
            y = viewportSize.height / 2
        } else {
            y = min(
                max(desiredY, actionStripSize.height / 2 + margin),
                viewportSize.height - actionStripSize.height / 2 - margin
            )
        }

        return CGPoint(x: x, y: y)
    }
}
