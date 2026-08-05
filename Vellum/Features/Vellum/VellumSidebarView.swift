import SwiftUI
import VellumCore

struct VellumSidebarView: View {
    @Environment(\.vellumWobble) private var vellumWobble
    @Bindable var model: VellumAppModel
    @State private var showingActivity = false
    @State private var showingSettings = false
    @State private var isImportingPDF = false
    @State private var pendingSpaceDeletion: Space?
    @State private var spaceEditor: SpaceEditorContext?

    var body: some View {
        let roots = model.spaceListings.filter { $0.space.parentID == nil }

        VStack(spacing: 0) {
            header
            newNoteMenu
            askButton
            navigationRows
            spacesHeader
            spaceList(roots)
            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .background(VellumTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(VellumTheme.ink(0.16))
                .frame(width: 1.5)
        }
        .sheet(isPresented: $showingActivity) {
            NavigationStack {
                ActivityView(workspace: model.container.workspace, noteID: nil)
            }
            .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .sheet(item: $spaceEditor) { context in
            SpaceEditorView(model: model, context: context)
                .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(model: model)
            }
            .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .pdfImporter(isPresented: $isImportingPDF, model: model)
        .confirmationDialog(
            "Delete '\(pendingSpaceDeletion?.name ?? "")'?",
            isPresented: Binding(
                get: { pendingSpaceDeletion != nil },
                set: { if !$0 { pendingSpaceDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let space = pendingSpaceDeletion {
                Button("Delete Space", role: .destructive) {
                    let id = space.id
                    pendingSpaceDeletion = nil
                    Task { await model.deleteSpace(id) }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingSpaceDeletion = nil
            }
        } message: {
            Text("Its subspaces are also removed, and all contained notes move to the Trash.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VellumLogoMark(size: 24)
            Text("Vellum")
                .font(.vellumSans(24, weight: .semibold))
                .tracking(0.3)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 16)
    }

    private var newNoteMenu: some View {
        Menu {
            Button("New Note", action: createNote)
            Button("New from PDF") {
                isImportingPDF = true
            }
        } label: {
            HStack(spacing: 9) {
                Text("+")
                    .font(.vellumSans(24, weight: .semibold))
                Text("new note")
                    .font(.vellumSans(18, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(VellumPillButtonStyle(.primary))
        .padding(.bottom, 12)
    }

    private var askButton: some View {
        let shape = OrganicPillShape(variant: 1, isOrganic: vellumWobble)

        return Button(action: model.goAskIdle) {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(VellumTheme.muted, lineWidth: 2)
                    .frame(width: 13, height: 13)
                Text("Ask Vellum…")
                    .font(.vellumSans(16, italic: true))
                Spacer()
            }
            .foregroundStyle(VellumTheme.mutedDark)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(VellumTheme.field, in: shape)
            .overlay {
                shape.strokeBorder(VellumTheme.ink(0.28), lineWidth: 1.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 18)
    }

    private var navigationRows: some View {
        VStack(spacing: 4) {
            VellumSidebarNavRow(
                id: "library",
                label: "Library",
                count: String(model.noteCount),
                variant: 0,
                model: model
            )
            VellumSidebarNavRow(
                id: "today",
                label: "Today",
                count: "",
                variant: 1,
                model: model
            )
            VellumSidebarNavRow(
                id: "graph",
                label: "Graph",
                count: "",
                variant: 2,
                model: model
            )
            VellumSidebarNavRow(
                id: "tasks",
                label: "Tasks",
                count: String(model.openTaskCount),
                variant: 3,
                model: model
            )
            VellumSidebarNavRow(
                id: "trash",
                label: "Compost",
                count: model.trashCount > 0 ? String(model.trashCount) : "",
                variant: 0,
                model: model
            )
        }
    }

    private var spacesHeader: some View {
        HStack(spacing: 8) {
            Text("SPACES")
                .font(.vellumMono(11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(VellumTheme.muted)
            VellumDottedLine(color: VellumTheme.ink(0.22))
                .frame(maxWidth: .infinity)
                .frame(height: 1.5)
            Button {
                spaceEditor = SpaceEditorContext(parent: nil)
            } label: {
                Text("+")
                    .font(.vellumSans(17, weight: .semibold))
                    .foregroundStyle(VellumTheme.mutedDark)
                    .frame(width: 26, height: 26)
                    .overlay {
                        OrganicPillShape(variant: 2, smallRadius: 9, isOrganic: vellumWobble)
                            .strokeBorder(VellumTheme.ink(0.3), lineWidth: 1.5)
                    }
                    .contentShape(
                        OrganicPillShape(variant: 2, smallRadius: 9, isOrganic: vellumWobble)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Space")
        }
        .padding(.horizontal, 10)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private func spaceList(_ roots: [SpaceListing]) -> some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(Array(roots.enumerated()), id: \.element.space.id) { rootIndex, root in
                    spaceRow(root, variant: rootIndex)
                    ForEach(
                        Array(model.spaceListings
                            .filter { $0.space.parentID == root.space.id }
                            .enumerated()),
                        id: \.element.space.id
                    ) { childIndex, child in
                        spaceRow(child, variant: rootIndex + childIndex + 1)
                            .padding(.leading, 18)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if model.showAgent {
                agentActivityLine
            }

            HStack(spacing: 8) {
                Button("settings") {
                    showingSettings = true
                }
                .font(.vellumMono(11.5))
                .tracking(0.6)
                .foregroundStyle(VellumTheme.mutedDark)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay {
                    OrganicPillShape(variant: 0, smallRadius: 16, isOrganic: vellumWobble)
                        .strokeBorder(VellumTheme.ink(0.26), lineWidth: 1.5)
                }
                .contentShape(
                    OrganicPillShape(variant: 0, smallRadius: 16, isOrganic: vellumWobble)
                )
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")

                Button("activity") {
                    showingActivity = true
                }
                .font(.vellumMono(11.5))
                .tracking(0.6)
                .foregroundStyle(VellumTheme.mutedDark)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay {
                    OrganicPillShape(variant: 1, smallRadius: 16, isOrganic: vellumWobble)
                        .strokeBorder(VellumTheme.ink(0.26), lineWidth: 1.5)
                }
                .contentShape(
                    OrganicPillShape(variant: 1, smallRadius: 16, isOrganic: vellumWobble)
                )
                .buttonStyle(.plain)
            }
        }
    }

    private var agentActivityLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(model.activityMessage) · \(model.activityCount) recent —")
                .lineLimit(2)
            Button("review") {
                showingActivity = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(VellumTheme.accentDark)
            .overlay(alignment: .bottom) {
                VellumDottedLine(color: VellumTheme.accent)
                    .frame(height: 1)
                    .offset(y: 1)
            }
        }
        .font(.vellumSans(14, italic: true))
        .foregroundStyle(VellumTheme.mutedDark)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(VellumTheme.ink(0.14))
                .frame(height: 1.5)
        }
    }

    private func spaceRow(_ listing: SpaceListing, variant: Int) -> some View {
        let selected = model.library.selectedSpaceID == listing.space.id
        let shape = OrganicPillShape(variant: variant, isOrganic: vellumWobble)

        return Button {
            model.library.selectedSpaceID = selected ? nil : listing.space.id
            Task { await model.navigate(to: .library) }
        } label: {
            HStack(spacing: 8) {
                VellumBlobDot(
                    color: VellumTheme.color(for: listing.space.color),
                    size: 9
                )
                Text(listing.space.name)
                    .font(.vellumSans(16.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? VellumTheme.ink : VellumTheme.bodyMuted)
                Spacer()
                Text(String(listing.noteCount))
                    .font(.vellumMono(12))
                    .foregroundStyle(VellumTheme.mutedCount)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 46)
            .background(selected ? VellumTheme.accent(0.13) : .clear, in: shape)
            .overlay {
                shape.strokeBorder(
                    selected ? VellumTheme.ink(0.45) : .clear,
                    lineWidth: 1.5
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if listing.space.parentID == nil {
                Button("New Subspace") {
                    spaceEditor = SpaceEditorContext(parent: listing.space)
                }
            }
            Button("Delete Space…", role: .destructive) {
                pendingSpaceDeletion = listing.space
            }
        }
    }

    private func createNote() {
        Task {
            guard let noteID = await model.library.createNote() else { return }
            await model.refreshStats()
            await model.openNote(noteID, isNewlyCreated: true)
        }
    }
}

private struct VellumSidebarNavRow: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let id: String
    let label: String
    let count: String
    let variant: Int
    @Bindable var model: VellumAppModel

    private var active: Bool {
        (id == "library" && model.screen == .library) ||
        (id == "today" && model.screen == .today) ||
        (id == "graph" && model.screen == .graph) ||
        (id == "tasks" && model.screen == .tasks) ||
        (id == "trash" && model.screen == .trash)
    }

    var body: some View {
        let shape = OrganicPillShape(variant: variant, isOrganic: vellumWobble)

        Button(action: activate) {
            HStack {
                Text(label)
                    .font(.vellumSans(18, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? VellumTheme.ink : VellumTheme.mutedDark)
                Spacer()
                Text(count)
                    .font(.vellumMono(12))
                    .foregroundStyle(active ? VellumTheme.accent : VellumTheme.mutedCount)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 48)
            .background(active ? VellumTheme.card : .clear, in: shape)
            .background {
                shape
                    .fill(active ? VellumTheme.ink(0.13) : .clear)
                    .offset(x: 3, y: 4)
            }
            .overlay {
                shape.strokeBorder(active ? VellumTheme.ink : .clear, lineWidth: 1.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private func activate() {
        switch id {
        case "library": Task { await model.navigate(to: .library) }
        case "today": Task { await model.navigate(to: .today) }
        case "graph": Task { await model.navigate(to: .graph) }
        case "tasks": Task { await model.navigate(to: .tasks) }
        case "trash": Task { await model.navigate(to: .trash) }
        default: break
        }
    }
}

struct VellumPencilGlyph: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 22
            var main = Path()
            main.move(to: CGPoint(x: 4 * scale, y: 18 * scale))
            main.addLine(to: CGPoint(x: 15 * scale, y: 7 * scale))
            context.stroke(main, with: .color(VellumTheme.paper), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
            var accent = Path()
            accent.move(to: CGPoint(x: 16.5 * scale, y: 5.5 * scale))
            accent.addLine(to: CGPoint(x: 18 * scale, y: 4 * scale))
            // Ink, not accent: the library's floating button fills its circle with
            // VellumTheme.accent, and an accent eraser tip disappears against it.
            context.stroke(accent, with: .color(VellumTheme.ink), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

struct VellumDottedLine: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 0.5))
            path.addLine(to: CGPoint(x: size.width, y: 0.5))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
    }
}
