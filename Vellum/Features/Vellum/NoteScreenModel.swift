import Foundation
import Observation
import UIKit
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
    let canvasElements = CanvasElementsStore()

    private let notes: any NoteRepository
    private let workspace: WorkspaceService
    private let graph: KnowledgeGraphService
    private let onNoteChanged: @MainActor (Note) -> Void

    private var pendingSaveTask: Task<Void, Never>?
    private var pendingSaveToken: UUID?
    private var editGeneration = 0
    private var savedGeneration = 0
    private var inFlightSave: Task<Void, Never>?
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
    var spaces: [SpaceListing] = []
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
        canvasElements.onElementsChanged = { [weak self] elements in
            self?.elementsChanged(elements)
        }
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

            let elements = loadedNote.pages.first?.elements ?? []
            note = loadedNote
            canvasElements.hydrate(elements)
            await cacheImages(for: elements, noteID: loadedNote.id)
            drawingData = drawing
            self.proposals = sortedProposals(proposals)
            self.spaces = spaces
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
            let referencedPaths = Set(loadedNote.pages.map(\.drawingAssetPath))
            try? await notes.purgeUnreferencedDrawingAssets(
                noteID: loadedNote.id,
                referencedPaths: referencedPaths
            )
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

    func elementsChanged(_ elements: [CanvasElement]) {
        guard var currentNote = note,
              !currentNote.pages.isEmpty,
              currentNote.pages[0].elements != elements else {
            return
        }
        currentNote.pages[0].elements = elements
        note = currentNote
        noteWasEdited()
    }

    func importImage(_ data: Data, visibleContentRect: CGRect) async {
        let processed: ImageImportPipeline.ProcessedImage
        do {
            processed = try await ImageImportPipeline.processForStorage(data)
        } catch {
            handle(error)
            return
        }

        let assetPath = "assets/\(UUID().uuidString).jpg"
        guard let note else {
            errorMessage = "The note must be loaded before inserting an image."
            return
        }

        do {
            try await notes.saveAsset(
                processed.jpegData,
                noteID: note.id,
                relativePath: assetPath
            )
        } catch {
            handle(error)
            return
        }

        let longEdge = max(processed.pixelSize.width, processed.pixelSize.height)
        let fittedLongEdge = 0.6 * min(
            visibleContentRect.width,
            visibleContentRect.height
        )
        let scale = fittedLongEdge / longEdge
        let fittedSize = CGSize(
            width: processed.pixelSize.width * scale,
            height: processed.pixelSize.height * scale
        )
        let frame = CanvasRect(
            x: Double(visibleContentRect.midX - fittedSize.width / 2),
            y: Double(visibleContentRect.midY - fittedSize.height / 2),
            width: Double(fittedSize.width),
            height: Double(fittedSize.height)
        )

        if let image = UIImage(data: processed.jpegData) {
            canvasElements.cacheImage(
                image,
                data: processed.jpegData,
                forAssetPath: assetPath
            )
        }
        canvasElements.addElement(
            CanvasElement(
                content: .image(
                    ImageContent(
                        assetPath: assetPath,
                        originalPixelSize: CanvasSize(
                            width: Double(processed.pixelSize.width),
                            height: Double(processed.pixelSize.height)
                        )
                    )
                ),
                frame: frame
            )
        )
    }

    func persistPastedImageData(_ data: Data) async -> String? {
        guard let note else {
            errorMessage = "The note must be loaded before pasting an image."
            return nil
        }
        let assetPath = "assets/\(UUID().uuidString).jpg"
        do {
            try await notes.saveAsset(
                data,
                noteID: note.id,
                relativePath: assetPath
            )
        } catch {
            handle(error)
            return nil
        }
        return assetPath
    }

    func flushPendingSave() async {
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

    func assignToSpace(_ spaceID: UUID?) async {
        await flushPendingSave()

        do {
            let updated = try await workspace.assignNote(id: noteID, toSpaceID: spaceID)
            let merged: Note
            if var currentNote = note {
                currentNote.spaceID = updated.spaceID
                currentNote.revision = updated.revision
                currentNote.updatedAt = updated.updatedAt
                currentNote.schemaVersion = updated.schemaVersion
                note = currentNote
                merged = currentNote
            } else {
                note = updated
                merged = updated
            }
            try await refreshSpace(for: merged)
            onNoteChanged(merged)
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
        if inFlightSave != nil {
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
        while let inFlight = inFlightSave {
            await inFlight.value
        }
        guard !autosaveDisabled else { return }
        while savedGeneration < editGeneration && !autosaveDisabled {
            let task = Task { [weak self] in
                guard let self else { return }
                await self.performSaveLoop()
            }
            inFlightSave = task
            await task.value
            inFlightSave = nil
        }
    }

    private func performSaveLoop() async {
        saveState = .saving

        while savedGeneration < editGeneration, !autosaveDisabled {
            guard var noteSnapshot = note else { return }
            let generationBeingSaved = editGeneration
            let drawingSnapshot = drawingDataPendingSave
            let oldAssetPath = noteSnapshot.pages.first?.drawingAssetPath
            var newAssetPath: String?

            do {
                if let drawingSnapshot, !noteSnapshot.pages.isEmpty {
                    let pageID = noteSnapshot.pages[0].id
                    let assetPath = "pages/\(pageID.uuidString)/drawing-\(UUID().uuidString).data"
                    try await notes.saveAsset(
                        drawingSnapshot,
                        noteID: noteSnapshot.id,
                        relativePath: assetPath
                    )
                    noteSnapshot.pages[0].drawingAssetPath = assetPath
                    newAssetPath = assetPath
                }

                let savedNote = try await workspace.saveNote(noteSnapshot)
                applySavedNote(
                    savedNote,
                    snapshot: noteSnapshot,
                    savedGeneration: generationBeingSaved,
                    savedDrawingData: drawingSnapshot,
                    newAssetPath: newAssetPath
                )
                if let newAssetPath,
                   let oldAssetPath,
                   newAssetPath != oldAssetPath {
                    try? await notes.deleteAsset(
                        noteID: noteSnapshot.id,
                        relativePath: oldAssetPath
                    )
                }
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
        savedDrawingData: Data?,
        newAssetPath: String?
    ) {
        savedGeneration = generation

        if generation == editGeneration {
            note = savedNote
        } else if var currentNote = note {
            currentNote.schemaVersion = savedNote.schemaVersion
            currentNote.revision = savedNote.revision
            currentNote.updatedAt = savedNote.updatedAt
            if let newAssetPath, !currentNote.pages.isEmpty {
                currentNote.pages[0].drawingAssetPath = newAssetPath
            }
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

    private func cacheImages(for elements: [CanvasElement], noteID: UUID) async {
        for element in elements {
            guard case .image(let content) = element.content else { continue }

            do {
                if let data = try await notes.loadAsset(
                    noteID: noteID,
                    relativePath: content.assetPath
                ),
                let image = UIImage(data: data) {
                    canvasElements.cacheImage(
                        image,
                        data: data,
                        forAssetPath: content.assetPath
                    )
                }
            } catch {
                continue
            }
        }
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
        let spaces = try await workspace.listSpaces()
        self.spaces = spaces
        space = spaces.first { $0.space.id == note.spaceID }?.space
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
