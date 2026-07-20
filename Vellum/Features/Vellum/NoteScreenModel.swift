import Foundation
import Observation
import VellumCore

@MainActor
@Observable
final class NoteScreenModel {
    enum EditorMode: String, CaseIterable, Identifiable {
        case ink = "Ink"
        case text = "Text"

        var id: Self { self }
    }

    enum SaveState: Equatable {
        case saved
        case saving
        case unsaved

        var label: String {
            switch self {
            case .saved: "Saved"
            case .saving: "Saving…"
            case .unsaved: "Unsaved changes"
            }
        }
    }

    let noteID: UUID

    private let notes: any NoteRepository
    private let workspace: WorkspaceService
    private let graph: KnowledgeGraphService
    private let onNoteChanged: @MainActor (Note) -> Void

    private var pendingSaveTask: Task<Void, Never>?
    private var pendingSaveToken: UUID?
    private var editGeneration = 0
    private var savedGeneration = 0
    private var isSaveInFlight = false
    private var drawingDataPendingSave: Data?
    private var autosaveDisabled = false

    var note: Note?
    var drawingData: Data?
    var proposals: [AgentProposal] = []
    var editorMode: EditorMode = .ink
    var saveState: SaveState = .saved
    var isLoading = false
    var isAnalyzing = false
    var errorMessage: String?

    var space: Space?
    var backlinks: [Backlink] = []
    var noteEntities: [Entity] = []
    var isShowingSuggestions = false
    var selectedEntity: Entity?
    var noteTitles: [UUID: String] = [:]

    var pendingProposals: [AgentProposal] {
        proposals.filter { $0.status == .pending }
    }

    init(
        noteID: UUID,
        container: AppContainer,
        onNoteChanged: @escaping @MainActor (Note) -> Void
    ) {
        self.noteID = noteID
        notes = container.notes
        workspace = container.workspace
        graph = container.graph
        self.onNoteChanged = onNoteChanged
    }

    var title: String {
        get { note?.title ?? "" }
        set {
            guard note?.title != newValue else { return }
            note?.title = newValue
            noteWasEdited()
        }
    }

    var plainText: String {
        get { note?.pages.first?.plainText ?? "" }
        set {
            guard var currentNote = note,
                  !currentNote.pages.isEmpty,
                  currentNote.pages[0].plainText != newValue else {
                return
            }
            currentNote.pages[0].plainText = newValue
            note = currentNote
            noteWasEdited()
        }
    }

    var hasEditablePage: Bool {
        note?.pages.isEmpty == false
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedNote = try await workspace.loadNote(id: noteID)
            async let loadedDrawing = loadDrawingAsset(for: loadedNote)
            async let loadedProposals = workspace.listProposals(noteID: noteID)
            async let loadedSpaces = workspace.listSpaces()
            async let loadedBacklinks = graph.backlinks(noteID: noteID)
            async let loadedEntities = graph.entities(noteID: noteID)
            async let loadedSummaries = workspace.listNoteSummaries()

            let (
                drawing,
                proposals,
                spaces,
                backlinks,
                entities,
                summaries
            ) = try await (
                loadedDrawing,
                loadedProposals,
                loadedSpaces,
                loadedBacklinks,
                loadedEntities,
                loadedSummaries
            )

            note = loadedNote
            drawingData = drawing
            self.proposals = sortedProposals(proposals)
            space = spaces.first { $0.space.id == loadedNote.spaceID }?.space
            self.backlinks = backlinks
            noteEntities = entities
            noteTitles = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0.title) })
            editGeneration = 0
            savedGeneration = 0
            drawingDataPendingSave = nil
            autosaveDisabled = false
            saveState = .saved
            errorMessage = nil
            onNoteChanged(loadedNote)
        } catch {
            handle(error)
        }
    }

    func drawingChanged(_ data: Data) {
        guard drawingData != data else { return }
        drawingData = data
        drawingDataPendingSave = data
        noteWasEdited()
    }

    func flushPendingSave() async {
        guard !autosaveDisabled else { return }

        if isSaveInFlight {
            let task = pendingSaveTask
            await task?.value
            return
        }

        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        pendingSaveToken = nil
        await saveUntilCurrent()
    }

    func organize() async {
        await flushPendingSave()
        guard !autosaveDisabled, savedGeneration == editGeneration else { return }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            _ = try await workspace.requestAnalysis(noteID: noteID)
            proposals = sortedProposals(
                try await workspace.listProposals(noteID: noteID)
            )
            try await refreshRelatedContent()
        } catch {
            handle(error)
        }
    }

    func refreshProposals() async {
        do {
            proposals = sortedProposals(
                try await workspace.listProposals(noteID: noteID)
            )
        } catch {
            handle(error)
        }
    }

    func accept(_ proposal: AgentProposal) async {
        await flushPendingSave()
        guard !autosaveDisabled, savedGeneration == editGeneration else { return }

        do {
            _ = try await workspace.acceptProposal(id: proposal.id)
            let reloadedNote = try await workspace.loadNote(id: noteID)
            let reloadedDrawing = try await loadDrawingAsset(for: reloadedNote)
            note = reloadedNote
            drawingData = reloadedDrawing
            drawingDataPendingSave = nil
            editGeneration = 0
            savedGeneration = 0
            saveState = .saved
            onNoteChanged(reloadedNote)
            proposals = sortedProposals(
                try await workspace.listProposals(noteID: noteID)
            )
            try await refreshSpace(for: reloadedNote)
            try await refreshRelatedContent()
        } catch let vellumError as VellumError {
            switch vellumError {
            case .staleProposal:
                await refreshProposals()
            default:
                handle(vellumError)
            }
        } catch {
            handle(error)
        }
    }

    func reject(_ proposal: AgentProposal) async {
        do {
            try await workspace.rejectProposal(id: proposal.id)
            proposals = sortedProposals(
                try await workspace.listProposals(noteID: noteID)
            )
        } catch {
            handle(error)
        }
    }

    private func noteWasEdited() {
        guard note != nil, !autosaveDisabled else { return }
        editGeneration += 1
        saveState = .unsaved
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        if isSaveInFlight {
            return
        }

        pendingSaveTask?.cancel()
        let token = UUID()
        pendingSaveToken = token
        pendingSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(600))
            } catch {
                return
            }
            guard let self else { return }
            await self.saveUntilCurrent()
            self.clearPendingSaveTask(matching: token)
        }
    }

    private func clearPendingSaveTask(matching token: UUID) {
        guard pendingSaveToken == token else { return }
        pendingSaveTask = nil
        pendingSaveToken = nil
    }

    private func saveUntilCurrent() async {
        guard !isSaveInFlight, !autosaveDisabled else { return }
        isSaveInFlight = true
        saveState = .saving
        defer { isSaveInFlight = false }

        while savedGeneration < editGeneration, !autosaveDisabled {
            guard let noteSnapshot = note else { return }
            let generationBeingSaved = editGeneration
            let drawingSnapshot = drawingDataPendingSave

            do {
                if let drawingSnapshot,
                   let assetPath = noteSnapshot.pages.first?.drawingAssetPath {
                    try await notes.saveAsset(
                        drawingSnapshot,
                        noteID: noteSnapshot.id,
                        relativePath: assetPath
                    )
                }

                let savedNote = try await workspace.saveNote(noteSnapshot)
                applySavedNote(
                    savedNote,
                    snapshot: noteSnapshot,
                    savedGeneration: generationBeingSaved,
                    savedDrawingData: drawingSnapshot
                )
                await refreshProposalsAfterSave()
            } catch {
                saveState = .unsaved
                handle(error)
                return
            }
        }

        if savedGeneration == editGeneration {
            saveState = .saved
        }
    }

    private func applySavedNote(
        _ savedNote: Note,
        snapshot: Note,
        savedGeneration generation: Int,
        savedDrawingData: Data?
    ) {
        savedGeneration = generation

        if generation == editGeneration {
            note = savedNote
        } else if var currentNote = note {
            currentNote.schemaVersion = savedNote.schemaVersion
            currentNote.revision = savedNote.revision
            currentNote.updatedAt = savedNote.updatedAt
            note = currentNote
        } else {
            note = savedNote
        }

        if drawingDataPendingSave == savedDrawingData {
            drawingDataPendingSave = nil
        }

        if let currentNote = note {
            onNoteChanged(currentNote)
        } else {
            onNoteChanged(snapshot)
        }
    }

    private func loadDrawingAsset(for note: Note) async throws -> Data? {
        guard let assetPath = note.pages.first?.drawingAssetPath else {
            return nil
        }
        return try await notes.loadAsset(
            noteID: note.id,
            relativePath: assetPath
        )
    }

    private func sortedProposals(_ proposals: [AgentProposal]) -> [AgentProposal] {
        proposals.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func refreshProposalsAfterSave() async {
        do {
            proposals = sortedProposals(
                try await workspace.listProposals(noteID: noteID)
            )
        } catch {
            handle(error)
        }
    }

    private func refreshRelatedContent() async throws {
        async let refreshedBacklinks = graph.backlinks(noteID: noteID)
        async let refreshedEntities = graph.entities(noteID: noteID)
        async let refreshedSummaries = workspace.listNoteSummaries()
        let (backlinks, entities, summaries) = try await (
            refreshedBacklinks,
            refreshedEntities,
            refreshedSummaries
        )
        self.backlinks = backlinks
        noteEntities = entities
        noteTitles = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0.title) })
    }

    private func refreshSpace(for note: Note) async throws {
        space = try await workspace.listSpaces()
            .first { $0.space.id == note.spaceID }?
            .space
    }

    private func handle(_ error: Error) {
        // Only a missing THIS note kills autosave; a noteNotFound for another
        // note (e.g. a link proposal whose target was deleted) must not.
        if case let VellumError.noteNotFound(missingID) = error, missingID == noteID {
            autosaveDisabled = true
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            pendingSaveToken = nil
        }
        errorMessage = error.localizedDescription
    }
}
