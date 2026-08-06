import SwiftUI
import VellumCore

struct NoteHeaderChips: View {
    @Environment(\.vellumWobble) private var vellumWobble
    @Bindable var model: NoteScreenModel
    let app: VellumAppModel
    var onShowActivity: () -> Void
    var onConfirmDelete: () -> Void
    var onExport: (NoteExporter.Format) -> Void
    var onClusterFrames: ((_ leading: CGRect, _ trailing: CGRect) -> Void)? = nil
    // Narrow split panes cannot fit the trailing cluster; it overflows the pane bounds.
    var isCompact: Bool = false

    @FocusState private var isTitleFocused: Bool
    @State private var reportedLeadingFrame: CGRect?
    @State private var reportedTrailingFrame: CGRect?
    @State private var headerRowFrame: CGRect = .zero

    var body: some View {
        HStack(alignment: .top) {
            leftCluster
                .onGeometryChange(
                    for: CGRect.self,
                    of: { $0.frame(in: .global) },
                    action: { frame in
                        reportedLeadingFrame = frame
                        notifyClusterFramesIfNeeded()
                    }
                )

            Spacer()

            if !isCompact {
                rightCluster
                    .onGeometryChange(
                        for: CGRect.self,
                        of: { $0.frame(in: .global) },
                        action: { frame in
                            reportedTrailingFrame = frame
                            notifyClusterFramesIfNeeded()
                        }
                    )
            }
        }
        .onGeometryChange(
            for: CGRect.self,
            of: { $0.frame(in: .global) },
            action: { frame in
                headerRowFrame = frame
                notifyClusterFramesIfNeeded()
            }
        )
    }

    private var leftCluster: some View {
        chip(
            strokeColor: isTitleFocused ? VellumTheme.accent(0.4) : nil
        ) {
            HStack(spacing: 10) {
                Button {
                    Task { await app.navigate(to: .library) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VellumTheme.accentDark)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Library")

                Rectangle()
                    .fill(VellumTheme.ink(0.12))
                    .frame(width: 1, height: 18)

                TextField("Untitled", text: $model.title)
                    .textFieldStyle(.plain)
                    .font(.vellumSans(18.5, weight: .medium))
                    .foregroundStyle(VellumTheme.ink)
                    .frame(minWidth: 90, idealWidth: 160, maxWidth: 200)
                    .frame(minHeight: 44)
                    .focused($isTitleFocused)
                    .accessibilityIdentifier("note-screen-title-field")

                Menu {
                    Button {
                        Task { await model.assignToSpace(nil) }
                    } label: {
                        spaceMenuItemLabel("Unfiled", isSelected: model.space == nil)
                    }

                    ForEach(
                        model.spaces.filter { $0.space.parentID == nil },
                        id: \.space.id
                    ) { root in
                        Button {
                            Task { await model.assignToSpace(root.space.id) }
                        } label: {
                            spaceMenuItemLabel(
                                root.space.name,
                                isSelected: model.space?.id == root.space.id
                            )
                        }

                        ForEach(
                            model.spaces.filter { $0.space.parentID == root.space.id },
                            id: \.space.id
                        ) { child in
                            Button {
                                Task { await model.assignToSpace(child.space.id) }
                            } label: {
                                spaceMenuItemLabel(
                                    "— \(child.space.name)",
                                    isSelected: model.space?.id == child.space.id
                                )
                            }
                        }
                    }
                } label: {
                    spaceChip
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
    }

    private var rightCluster: some View {
        chip {
            HStack(spacing: 10) {
                Button {
                    Task { await model.organize() }
                } label: {
                    if model.isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Organizing")
                    } else {
                        Label("Organize", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.plain)
                .font(.vellumSans(16.5, weight: .medium))
                .foregroundStyle(VellumTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    VellumTheme.highlight.opacity(0.24),
                    in: OrganicPillShape(variant: 1, smallRadius: 8, isOrganic: vellumWobble)
                )
                .overlay {
                    OrganicPillShape(variant: 1, smallRadius: 8, isOrganic: vellumWobble)
                        .strokeBorder(VellumTheme.ink(0.24), lineWidth: 1)
                }
                .frame(minHeight: 44)
                .disabled(model.isAnalyzing || model.note == nil)

                Menu {
                    ForEach(NoteExporter.Format.allCases, id: \.rawValue) { format in
                        Button("Export as \(format.displayName)") {
                            onExport(format)
                        }
                    }
                } label: {
                    Text("Share")
                }
                .buttonStyle(.plain)
                .font(.vellumSans(16.5, weight: .medium))
                .foregroundStyle(VellumTheme.mutedDark)
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .disabled(model.isLoading || model.note == nil)

                Menu {
                    Section {
                        Text(saveStateLabel)
                    }

                    Button {
                        onShowActivity()
                    } label: {
                        Label("Activity", systemImage: "clock.arrow.circlepath")
                    }

                    Button(role: .destructive) {
                        onConfirmDelete()
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                } label: {
                    Text("⋯")
                        .font(.system(size: 17))
                        .frame(minWidth: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")
                .frame(minHeight: 44)
            }
            .foregroundStyle(VellumTheme.mutedDark)
        }
    }

    @ViewBuilder
    private var spaceChip: some View {
        if let space = model.space {
            spaceBadge(
                space.name,
                color: VellumTheme.color(for: space.color)
            )
        } else {
            spaceBadge("Unfiled", color: VellumTheme.spaceGray)
        }
    }

    private func spaceBadge(_ name: String, color: Color) -> some View {
        let shape = OrganicPillShape(variant: 2, smallRadius: 10, isOrganic: vellumWobble)
        return HStack(spacing: 6) {
            VellumBlobDot(color: color, size: 7)
            Text(name)
                .lineLimit(1)
        }
        .font(.vellumSans(14, weight: .medium))
        .foregroundStyle(VellumTheme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.16), in: shape)
        .overlay {
            shape.strokeBorder(color.opacity(0.4), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func spaceMenuItemLabel(_ name: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(name, systemImage: "checkmark")
        } else {
            Text(name)
        }
    }

    private var saveStateLabel: String {
        switch model.saveState {
        case .saved: "saved · on-device"
        case .saving: "saving…"
        case .unsaved: "unsaved"
        }
    }

    private func chip<Content: View>(
        strokeColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .vellumFloatingChrome(
                .pill(variant: 0),
                strokeColor: strokeColor
            )
    }

    private func notifyClusterFramesIfNeeded() {
        guard let leading = reportedLeadingFrame else { return }
        if isCompact {
            guard headerRowFrame != .zero else { return }
            // Compact panes use the row edge so the zero-width trailing frame remains valid geometry.
            let synthesizedTrailing = CGRect(
                x: headerRowFrame.maxX,
                y: leading.minY,
                width: 0,
                height: leading.height
            )
            onClusterFrames?(leading, synthesizedTrailing)
            return
        }
        guard let trailing = reportedTrailingFrame else { return }
        onClusterFrames?(leading, trailing)
    }
}
