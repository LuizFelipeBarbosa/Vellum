import SwiftUI

struct SelectionActionStripView: View {
    /// Strip actions and calibrated width estimates for the fixed 12.5pt-medium font and current
    /// label padding. The estimates size the strip frame; SwiftUI still lays out each button.
    enum StripAction: CaseIterable, Hashable {
        case cut
        case copy
        case style
        case arrange
        case duplicate
        case delete

        var title: String {
            switch self {
            case .cut: "Cut"
            case .copy: "Copy"
            case .style: "Style"
            case .arrange: "Arrange"
            case .duplicate: "Duplicate"
            case .delete: "Delete"
            }
        }

        var systemImage: String {
            switch self {
            case .cut: "scissors"
            case .copy: "doc.on.doc"
            case .style: "paintpalette"
            case .arrange: "square.2.layers.3d"
            case .duplicate: "plus.square.on.square"
            case .delete: "trash"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .cut: "Cut selection"
            case .copy: "Copy selection"
            case .style: "Style selection"
            case .arrange: "Arrange selection"
            case .duplicate: "Duplicate selection"
            case .delete: "Delete selection"
            }
        }

        /// Calibrated estimate of this button's rendered width (icon + label + horizontal padding)
        /// at the strip's fixed 12.5pt-medium font.
        var nominalWidth: CGFloat {
            switch self {
            case .cut: 62
            case .copy: 72
            case .style: 76
            case .arrange: 96
            case .duplicate: 108
            case .delete: 76
            }
        }
    }

    let controller: CanvasSelectionController

    @State private var isShowingStylePopover = false
    @State private var isShowingArrangePopover = false
    @State private var styleColor = ToolPreferences.default.pen.color
    @State private var styleWidth = ToolPreferences.default.pen.width

    var body: some View {
        actionStrip
    }

    private var actionStrip: some View {
        HStack(spacing: 4) {
            ForEach(
                Self.actions(includesStyle: controller.selectionSupportsStyling),
                id: \.self
            ) { action in
                actionButton(for: action)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(VellumTheme.mutedDark)
        .frame(
            width: Self.stripSize(
                includesStyle: controller.selectionSupportsStyling
            ).width,
            height: 40
        )
        .background(VellumTheme.popover, in: Capsule())
        .overlay {
            Capsule().stroke(VellumTheme.ink(0.12), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
    }

    @ViewBuilder
    private func actionButton(for action: StripAction) -> some View {
        switch action {
        case .cut:
            Button {
                controller.cutSelection()
            } label: {
                actionLabel(action.title, systemImage: action.systemImage)
            }
            .accessibilityLabel(action.accessibilityLabel)
        case .copy:
            Button {
                controller.copySelection()
            } label: {
                actionLabel(action.title, systemImage: action.systemImage)
            }
            .accessibilityLabel(action.accessibilityLabel)
        case .style:
            Button {
                isShowingStylePopover.toggle()
            } label: {
                actionLabel(action.title, systemImage: action.systemImage)
            }
            .accessibilityLabel(action.accessibilityLabel)
            .popover(isPresented: $isShowingStylePopover) {
                stylePopover
            }
        case .arrange:
            Button {
                isShowingArrangePopover.toggle()
            } label: {
                actionLabel(action.title, systemImage: action.systemImage)
            }
            .accessibilityLabel(action.accessibilityLabel)
            .popover(isPresented: $isShowingArrangePopover) {
                arrangePopover
            }
        case .duplicate:
            Button {
                controller.duplicateSelection()
            } label: {
                actionLabel(action.title, systemImage: action.systemImage)
            }
            .accessibilityLabel(action.accessibilityLabel)
        case .delete:
            Button(role: .destructive) {
                controller.deleteSelection()
            } label: {
                actionLabel(action.title, systemImage: action.systemImage)
            }
            .foregroundStyle(.red)
            .accessibilityLabel(action.accessibilityLabel)
        }
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

    private var arrangePopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            arrangeButton(
                "Flip Horizontal",
                systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                accessibilityLabel: "Flip selection horizontally"
            ) {
                controller.flipSelection(horizontal: true)
            }

            arrangeButton(
                "Flip Vertical",
                systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                accessibilityLabel: "Flip selection vertically"
            ) {
                controller.flipSelection(horizontal: false)
            }

            Divider()
                .padding(.vertical, 6)

            arrangeButton(
                "Bring to Front",
                systemImage: "square.3.layers.3d.top.filled",
                accessibilityLabel: "Bring selection to front"
            ) {
                controller.reorderSelection(.toFront)
            }
            .disabled(!controller.canReorderSelection)

            arrangeButton(
                "Bring Forward",
                systemImage: "square.2.layers.3d.top.filled",
                accessibilityLabel: "Bring selection forward"
            ) {
                controller.reorderSelection(.forward)
            }
            .disabled(!controller.canReorderSelection)

            arrangeButton(
                "Send Backward",
                systemImage: "square.2.layers.3d.bottom.filled",
                accessibilityLabel: "Send selection backward"
            ) {
                controller.reorderSelection(.backward)
            }
            .disabled(!controller.canReorderSelection)

            arrangeButton(
                "Send to Back",
                systemImage: "square.3.layers.3d.bottom.filled",
                accessibilityLabel: "Send selection to back"
            ) {
                controller.reorderSelection(.toBack)
            }
            .disabled(!controller.canReorderSelection)
        }
        .padding(18)
        .frame(width: 230, alignment: .leading)
        .background(VellumTheme.popover)
    }

    private func arrangeButton(
        _ title: String,
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    static func actions(includesStyle: Bool) -> [StripAction] {
        includesStyle ? StripAction.allCases : StripAction.allCases.filter { $0 != .style }
    }

    static func stripSize(includesStyle: Bool) -> CGSize {
        let spacing: CGFloat = 4
        let visible = actions(includesStyle: includesStyle)
        let width = visible.reduce(0) { $0 + $1.nominalWidth }
            + spacing * CGFloat(max(visible.count - 1, 0))
        return CGSize(width: width, height: 40)
    }

    /// Places the strip fully above `avoidRect` when it fits, else fully below, else pinned
    /// inside the viewport's bottom edge (only when no non-overlapping placement exists —
    /// bottom is chosen because pinning top would cover the rotation handle).
    /// View-space inputs. Pure; unit tested.
    static func position(avoiding avoidRect: CGRect, stripSize: CGSize, in viewportSize: CGSize) -> CGPoint {
        let margin: CGFloat = 8
        let gap: CGFloat = 12

        let x: CGFloat
        if viewportSize.width < stripSize.width + margin * 2 {
            x = viewportSize.width / 2
        } else {
            x = min(
                max(avoidRect.midX, stripSize.width / 2 + margin),
                viewportSize.width - stripSize.width / 2 - margin
            )
        }

        let aboveY = avoidRect.minY - gap - stripSize.height / 2
        let aboveFits = avoidRect.minY - gap - stripSize.height >= margin

        let belowY = avoidRect.maxY + gap + stripSize.height / 2
        let belowFits = avoidRect.maxY + gap + stripSize.height <= viewportSize.height - margin

        let y: CGFloat
        if aboveFits {
            y = aboveY
        } else if belowFits {
            y = belowY
        } else if viewportSize.height < stripSize.height + margin * 2 {
            y = viewportSize.height / 2
        } else {
            y = viewportSize.height - margin - stripSize.height / 2
        }

        return CGPoint(x: x, y: y)
    }
}
