import SwiftUI
import VellumCore

struct VellumSidebarView: View {
    @Bindable var model: VellumAppModel
    @State private var showingActivity = false
    @State private var showingSettings = false
    @State private var isImportingPDF = false
    @State private var pendingSpaceDeletion: Space?
    @State private var spaceEditor: SpaceEditorContext?

    var body: some View {
        let roots = model.spaceListings.filter { $0.space.parentID == nil }

        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    VellumLogoMark(size: 21)
                    Text("Vellum")
                        .font(.vellumNewsreader(21, weight: .semibold))
                        .tracking(0.42)
                }
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(VellumTheme.mutedControl)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                Menu {
                    Button("New Note", action: createNote)
                    Button("New from PDF") {
                        isImportingPDF = true
                    }
                } label: {
                    VellumPencilGlyph(size: 15)
                        .frame(width: 30, height: 30)
                        .background(VellumTheme.ink, in: RoundedRectangle(cornerRadius: 9))
                        .shadow(color: VellumTheme.ink(0.25), radius: 3, y: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 18)

            Button(action: model.goAskIdle) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                    Text("Ask Vellum…")
                        .font(.system(size: 14))
                    Spacer()
                }
                .foregroundStyle(VellumTheme.mutedControl)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(VellumTheme.ink(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)

            VStack(spacing: 2) {
                VellumSidebarNavRow(
                    id: "library",
                    label: "Library",
                    count: String(model.noteCount),
                    model: model
                )
                VellumSidebarNavRow(id: "today", label: "Today", count: "", model: model)
                VellumSidebarNavRow(id: "graph", label: "Graph", count: "", model: model)
                VellumSidebarNavRow(
                    id: "tasks",
                    label: "Tasks",
                    count: String(model.openTaskCount),
                    model: model
                )
                VellumSidebarNavRow(
                    id: "trash",
                    label: "Trash",
                    count: model.trashCount > 0 ? String(model.trashCount) : "",
                    model: model
                )
            }

            HStack {
                Text("SPACES")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.99)
                Spacer()
                Button {
                    spaceEditor = SpaceEditorContext(parent: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Space")
            }
            .foregroundStyle(VellumTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 24)
            .padding(.bottom, 8)

            VStack(spacing: 2) {
                ForEach(roots, id: \.space.id) { root in
                    spaceRow(root)
                    ForEach(
                        model.spaceListings.filter { $0.space.parentID == root.space.id },
                        id: \.space.id
                    ) { child in
                        spaceRow(child)
                            .padding(.leading, 18)
                    }
                }
            }

            Spacer(minLength: 16)

            if model.showAgent {
                HStack(spacing: 3) {
                    Text("\(model.activityMessage) · \(model.activityCount) recent —")
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
                .font(.vellumNewsreader(12, italic: true))
                .foregroundStyle(VellumTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .overlay(alignment: .top) {
                    Rectangle().fill(VellumTheme.ink(0.08)).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(VellumTheme.paper)
        .overlay(alignment: .trailing) {
            Rectangle().fill(VellumTheme.ink(0.09)).frame(width: 1)
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

    private func spaceRow(_ listing: SpaceListing) -> some View {
        let selected = model.library.selectedSpaceID == listing.space.id

        return Button {
            model.library.selectedSpaceID = selected ? nil : listing.space.id
            Task { await model.navigate(to: .library) }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(VellumTheme.color(for: listing.space.color))
                    .frame(width: 7, height: 7)
                Text(listing.space.name)
                Spacer()
                Text(String(listing.noteCount))
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? VellumTheme.accent : VellumTheme.mutedCount)
            }
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? VellumTheme.ink : VellumTheme.bodyMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selected ? VellumTheme.accent(0.1) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
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
    let id: String
    let label: String
    let count: String
    @Bindable var model: VellumAppModel

    private var active: Bool {
        (id == "library" && model.screen == .library) ||
        (id == "graph" && model.screen == .graph) ||
        (id == "trash" && model.screen == .trash)
    }

    var body: some View {
        Button(action: activate) {
            HStack {
                Text(label)
                Spacer()
                Text(count)
                    .font(.system(size: 12))
                    .foregroundStyle(active ? VellumTheme.accent : VellumTheme.mutedCount)
            }
            .font(.system(size: 14, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? VellumTheme.ink : VellumTheme.bodyMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(active ? VellumTheme.accent(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activate() {
        switch id {
        case "library": Task { await model.navigate(to: .library) }
        case "graph": Task { await model.navigate(to: .graph) }
        case "trash": Task { await model.navigate(to: .trash) }
        case "today": model.showToast("Today — the daily digest isn’t in this proto" + "type yet")
        case "tasks": model.showToast("Tasks — extracted to-dos live here (not in proto" + "type)")
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
            context.stroke(accent, with: .color(VellumTheme.accent), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
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
