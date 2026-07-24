import Observation
import SwiftUI
import VellumCore

struct NoteHeaderChips: View {
    @Bindable var model: NoteScreenModel
    let app: VellumAppModel
    var onShowActivity: () -> Void
    var onConfirmDelete: () -> Void
    var onExport: (NoteExporter.Format) -> Void
    var onClusterFrames: ((_ leading: CGRect, _ trailing: CGRect) -> Void)? = nil

    @FocusState private var isTitleFocused: Bool
    @State private var reportedLeadingFrame: CGRect?
    @State private var reportedTrailingFrame: CGRect?

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

    private var leftCluster: some View {
        chip(
            strokeColor: isTitleFocused
                ? VellumTheme.accent(0.4)
                : VellumTheme.ink(0.12)
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
                    .font(.vellumNewsreader(18, weight: .medium))
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
            HStack(spacing: 14) {
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
            .font(.system(size: 13))
            .foregroundStyle(VellumTheme.mutedDark)
        }
    }

    @ViewBuilder
    private var spaceChip: some View {
        if let space = model.space {
            HStack(spacing: 6) {
                Circle()
                    .fill(VellumTheme.color(for: space.color))
                    .frame(width: 6, height: 6)
                Text(space.name)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(VellumTheme.accentDark)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(VellumTheme.accent(0.12), in: Capsule())
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(VellumTheme.muted)
                    .frame(width: 6, height: 6)
                Text("Unfiled")
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(VellumTheme.mutedDark)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(VellumTheme.muted.opacity(0.12), in: Capsule())
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
        strokeColor: Color = VellumTheme.ink(0.12),
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .background(
                VellumTheme.popover,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            }
            .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
    }

    private func notifyClusterFramesIfNeeded() {
        guard let leading = reportedLeadingFrame,
              let trailing = reportedTrailingFrame else { return }
        onClusterFrames?(leading, trailing)
    }
}
