import Observation
import PencilKit
import SwiftUI
import VellumCore

struct NoteScreenView: View {
    @Bindable var model: NoteScreenModel
    @Bindable var app: VellumAppModel

    @State private var isShowingActivity = false
    @State private var isConfirmingDelete = false
    @State private var selectedTool: NoteDrawingTool = .pen
    @State private var selectedColor: NoteInkColor = .ink
    @State private var canvasReference = NoteCanvasReference()

    var body: some View {
        VStack(spacing: 0) {
            header

            if !model.noteEntities.isEmpty {
                entityChips
            }

            Group {
                if model.isLoading && model.note == nil {
                    ProgressView("Loading note…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(VellumTheme.card)
                } else if model.note != nil {
                    canvasArea
                } else {
                    ContentUnavailableView(
                        "Note Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The note could not be loaded.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(VellumTheme.card)
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(VellumTheme.ink(0.08))
                    .frame(height: 1)
            }
        }
        .background(VellumTheme.paper)
        .task {
            if model.note == nil {
                await model.load()
            }
        }
        .onChange(of: model.pendingProposals.count) { _, count in
            if count == 0 {
                model.isShowingSuggestions = false
            }
        }
        .sheet(isPresented: $isShowingActivity) {
            NavigationStack {
                ActivityView(
                    workspace: app.container.workspace,
                    noteID: model.noteID
                )
            }
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Note", role: .destructive) {
                deleteNote()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the note and its local assets.")
        }
        .alert(
            "Vellum",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { model.errorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "An unknown error occurred.")
        }
        .animation(.easeOut(duration: 0.18), value: model.selectedEntity?.id)
        .animation(.easeOut(duration: 0.2), value: model.isShowingSuggestions)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                Task { await app.navigate(to: .library) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Library")
                }
                .font(.system(size: 15))
                .foregroundStyle(VellumTheme.accentDark)
            }
            .buttonStyle(.plain)

            TextField("Untitled", text: $model.title)
                .textFieldStyle(.plain)
                .font(.vellumNewsreader(18, weight: .medium))
                .foregroundStyle(VellumTheme.ink)
                .frame(minWidth: 180, idealWidth: 300, maxWidth: 390)
                .accessibilityIdentifier("note-screen-title-field")

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
            }

            Text(saveStateLabel)
                .font(.vellumMono(11))
                .foregroundStyle(VellumTheme.mutedCount)

            Spacer(minLength: 8)

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
            .disabled(model.isAnalyzing || model.note == nil)

            Button("Share") {
                app.showToast("Share — exports the page or its Open Knowledge Format")
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    isShowingActivity = true
                } label: {
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Text("⋯")
                    .font(.system(size: 17))
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13))
        .foregroundStyle(VellumTheme.mutedDark)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var entityChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.noteEntities) { entity in
                    Button {
                        model.selectedEntity = entity
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(entityColor(for: entity.kind))
                                .frame(width: 6, height: 6)
                            Text(entity.name)
                                .lineLimit(1)
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(VellumTheme.bodyMuted)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(VellumTheme.card, in: Capsule())
                        .overlay {
                            Capsule().stroke(VellumTheme.ink(0.13), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 9)
        }
        .scrollIndicators(.hidden)
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VellumDotGrid(
                    spacing: 24,
                    dotColor: VellumTheme.ink(0.12),
                    background: VellumTheme.card
                )

                PencilCanvasView(
                    drawingData: model.drawingData,
                    onDrawingChanged: { data in
                        model.drawingChanged(data)
                    },
                    isTransparent: true,
                    tool: activeTool,
                    showsSystemToolPicker: false,
                    onCanvasReady: { canvasView in
                        canvasReference.canvasView = canvasView
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                backlinksRail
                    .frame(width: 184)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 34)
                    .zIndex(2)

                if let entity = model.selectedEntity {
                    EntityPopoverView(entity: entity, model: model, app: app)
                        .frame(width: 270)
                        .padding(.leading, 80)
                        .padding(.top, 30)
                        .transition(.offset(y: 6).combined(with: .opacity))
                        .zIndex(5)
                }

                if !model.pendingProposals.isEmpty {
                    agentLine
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 80)
                        .padding(.bottom, 92)
                        .zIndex(3)
                }

                NoteToolbarView(
                    selectedTool: $selectedTool,
                    selectedColor: $selectedColor,
                    canvasReference: canvasReference
                )
                .fixedSize()
                .position(x: geometry.size.width / 2, y: geometry.size.height - 43)
                .zIndex(4)

                if model.isShowingSuggestions {
                    suggestionsOverlay
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .clipped()
        }
    }

    private var backlinksRail: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(model.backlinks, id: \.sourceNoteID) { backlink in
                Button {
                    Task {
                        await app.navigate(to: .note(backlink.sourceNoteID))
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(backlink.sourceTitle)
                            .foregroundStyle(VellumTheme.bodyMuted)
                            .lineLimit(1)
                        Text("· \(backlink.kind.rawValue)")
                            .foregroundStyle(VellumTheme.mutedCount)
                    }
                    .font(.system(size: 12.5))
                    .padding(.leading, 16)
                    .padding(.trailing, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        VellumTheme.card,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 10,
                            bottomLeadingRadius: 10
                        )
                    )
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 10,
                            bottomLeadingRadius: 10
                        )
                        .stroke(VellumTheme.ink(0.14), lineWidth: 1)
                    }
                    .shadow(color: VellumTheme.ink(0.06), radius: 3, x: -2, y: 2)
                }
                .buttonStyle(.plain)
            }

            Text("\(model.backlinks.count) \(model.backlinks.count == 1 ? "backlink" : "backlinks")")
                .font(.vellumMono(10.5))
                .foregroundStyle(VellumTheme.mutedCount)
                .padding(.trailing, 14)
        }
    }

    private var agentLine: some View {
        Button {
            model.isShowingSuggestions = true
        } label: {
            HStack(spacing: 3) {
                Text("\(model.pendingProposals.count) suggestions —")
                Text("review")
                    .foregroundStyle(VellumTheme.accentDark)
                    .overlay(alignment: .bottom) {
                        VellumDottedLine(color: VellumTheme.accent)
                            .frame(height: 1)
                            .offset(y: 1)
                    }
            }
            .font(.vellumNewsreader(13.5, italic: true))
            .foregroundStyle(VellumTheme.muted)
        }
        .buttonStyle(.plain)
    }

    private var suggestionsOverlay: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.isShowingSuggestions = false
                }

            suggestionsPanel
                .frame(width: 370)
                .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var suggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggestions")
                        .font(.vellumNewsreader(22, weight: .semibold))
                    Text("\(model.pendingProposals.count) ready to review")
                        .font(.vellumMono(10.5))
                        .foregroundStyle(VellumTheme.mutedCount)
                }
                Spacer()
                Button("×") {
                    model.isShowingSuggestions = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 18))
                .foregroundStyle(VellumTheme.mutedCount)
                .accessibilityLabel("Close suggestions")
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.pendingProposals) { proposal in
                        suggestionCard(proposal)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.18), radius: 18, x: -4, y: 12)
    }

    private func suggestionCard(_ proposal: AgentProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.title)
                    .font(.vellumNewsreader(16, weight: .semibold))
                    .foregroundStyle(VellumTheme.ink)
                Spacer()
                Text("\(Int((proposal.confidence * 100).rounded()))%")
                    .font(.vellumMono(10.5, weight: .medium))
                    .foregroundStyle(VellumTheme.accentDark)
            }

            Text(operationDescription(proposal.operation))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(VellumTheme.bodyMuted)

            Text(proposal.explanation)
                .font(.system(size: 12.5))
                .foregroundStyle(VellumTheme.mutedDark)
                .lineSpacing(4)

            HStack(spacing: 10) {
                Button("Accept") {
                    Task { await model.accept(proposal) }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(VellumTheme.paper)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(VellumTheme.ink, in: Capsule())

                Button("Reject") {
                    Task { await model.reject(proposal) }
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(VellumTheme.mutedDark)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VellumTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(VellumTheme.ink(0.1), lineWidth: 1)
        }
    }

    private var activeTool: any PKTool {
        switch selectedTool {
        case .pen:
            PKInkingTool(
                .pen,
                color: UIColor(selectedColor.color),
                width: 4
            )
        case .highlighter:
            PKInkingTool(
                .marker,
                color: UIColor(VellumTheme.accent).withAlphaComponent(0.55),
                width: 12
            )
        case .eraser:
            PKEraserTool(.vector)
        case .lasso:
            PKLassoTool()
        }
    }

    private var saveStateLabel: String {
        switch model.saveState {
        case .saved: "saved · on-device"
        case .saving: "saving…"
        case .unsaved: "unsaved"
        }
    }

    private func entityColor(for kind: EntityKind) -> Color {
        switch kind {
        case .person: VellumTheme.accent
        case .topic: VellumTheme.thesis
        case .document: VellumTheme.spaceBlue
        }
    }

    private func operationDescription(_ operation: AgentOperation) -> String {
        switch operation {
        case .addTag(let tag):
            "Add tag “\(tag)”"
        case .suggestTitle(let title):
            "Rename note to “\(title)”"
        case .createSummary(let summary):
            "Create summary: \(summary)"
        case .fileToSpace(let spaceName, let color):
            "File in \(spaceName) · \(color.rawValue)"
        case .linkNotes(let targetNoteID, let kind):
            "Link to \(model.noteTitles[targetNoteID] ?? targetNoteID.uuidString) · \(kind.rawValue)"
        case .extractTask(let text, _):
            "Extract task: \(text)"
        case .extractEntity(let name, let kind, _, _):
            "Extract \(kind.rawValue): \(name)"
        }
    }

    private func deleteNote() {
        Task {
            do {
                try await app.deleteCurrentNote(id: model.noteID)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
}
