import Foundation
import Observation
import PDFKit
import PencilKit
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

    enum PDFLoadFailureReason: Equatable {
        case missing
        case loadError(String)
        case undecodable
    }

    let noteID: UUID
    let offersBackgroundChooser: Bool
    let canvasElements = CanvasElementsStore()
    let pdfCache = PdfPageImageCache()

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
    private var pendingPageMutationSave = false

    var note: Note?
    var drawingData: Data?
    var proposals: [AgentProposal] = []
    var editorMode: EditorMode = .ink
    var saveState: SaveState = .saved
    var isLoading = false
    var isAnalyzing = false
    var errorMessage: String?
    private(set) var pdfLoadFailures: [String: PDFLoadFailureReason] = [:]

    var space: Space?
    var spaces: [SpaceListing] = []
    var backlinks: [Backlink] = []
    var noteEntities: [Entity] = []
    var isShowingSuggestions = false
    var isShowingBackgroundChooser = false
    var selectedEntity: Entity?
    var noteTitles: [UUID: String] = [:]
    var onScrollToPage: ((Int) -> Void)?

    var pendingProposals: [AgentProposal] {
        proposals.filter { $0.status == .pending }
    }

    init(
        noteID: UUID,
        container: AppContainer,
        offersBackgroundChooser: Bool = false,
        onNoteChanged: @escaping @MainActor (Note) -> Void
    ) {
        self.noteID = noteID
        self.offersBackgroundChooser = offersBackgroundChooser
        notes = container.notes
        workspace = container.workspace
        graph = container.graph
        self.onNoteChanged = onNoteChanged
        canvasElements.onElementsChanged = { [weak self] elements in
            self?.elementsChanged(elements)
        }
        canvasElements.pagesProvider = { [weak self] in
            self?.note?.pages ?? []
        }
        pdfCache.pagesProvider = { [weak self] in
            self?.note?.pages ?? []
        }
        canvasElements.onPagesRestored = { [weak self] pages in
            self?.pagesRestored(pages)
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

    var backgroundStyle: PageBackgroundStyle {
        get { note?.backgroundStyle ?? .legacyDefault }
        set {
            guard var current = note, current.backgroundStyle != newValue else { return }
            current.backgroundStyle = newValue
            note = current
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

    var pdfBands: Set<Int> {
        guard let pages = note?.pages else { return [] }
        return Set(pages.indices.filter { pages[$0].pdfPage != nil })
    }

    var pdfLoadFailureMessage: String? {
        guard !pdfLoadFailures.isEmpty else { return nil }
        let count = pdfLoadFailures.count
        return "Couldn't load the PDF for \(count) page\(count == 1 ? "" : "s") — pull to retry or reopen the note."
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
            await cachePDFDocuments(for: loadedNote)
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
            if let message = pdfLoadFailureMessage {
                errorMessage = message
            }
            onNoteChanged(loadedNote)
            try? await notes.purgeUnreferencedAssets(noteID: loadedNote.id)

            let loadedPKDrawing: PKDrawing
            if let drawing {
                guard let decodedDrawing = try? PKDrawing(data: drawing) else {
                    errorMessage = "The note's ink could not be read, so it is shown empty."
                    return
                }
                loadedPKDrawing = decodedDrawing
            } else {
                loadedPKDrawing = PKDrawing()
            }

            if loadedNote.layoutVersion < Note.currentLayoutVersion {
                let migration = LegacyContentMigrator.migrateIfNeeded(
                    drawing: loadedPKDrawing,
                    elements: elements,
                    layoutVersion: loadedNote.layoutVersion
                )
                if migration.didMigrate {
                    drawingChanged(migration.drawing.dataRepresentation())
                    canvasElements.hydrate(migration.elements)
                    elementsChanged(migration.elements)
                }

                guard var currentNote = note else { return }
                currentNote.layoutVersion = Note.currentLayoutVersion
                note = currentNote
                noteWasEdited()
            }
            isShowingBackgroundChooser = offersBackgroundChooser
        } catch {
            handle(error)
        }
    }

    func retryPDFLoad() async {
        guard let currentNote = note else { return }
        let wasShowingPDFFailureMessage =
            errorMessage != nil && errorMessage == pdfLoadFailureMessage
        await cachePDFDocuments(for: currentNote)
        if let message = pdfLoadFailureMessage {
            errorMessage = message
        } else if wasShowingPDFFailureMessage {
            errorMessage = nil
        }
    }

    func drawingChanged(_ data: Data) {
        guard drawingData != data else { return }
        drawingData = data
        drawingDataPendingSave = data
        noteWasEdited()
        materializePagesForFilledBands()
    }

    func elementsChanged(_ elements: [CanvasElement]) {
        let pagesNeedSave = pendingPageMutationSave
        pendingPageMutationSave = false

        guard var currentNote = note, !currentNote.pages.isEmpty else {
            return
        }

        let elementsDidChange = currentNote.pages[0].elements != elements
        if elementsDidChange {
            currentNote.pages[0].elements = elements
            note = currentNote
        }
        if elementsDidChange || pagesNeedSave {
            noteWasEdited()
        }
        materializePagesForFilledBands()
    }

    func materializePagesForFilledBands() {
        guard var currentNote = note else { return }

        let drawingBounds: CGRect
        if let liveDrawing = canvasElements.canvasReference?.canvasView?.drawing {
            drawingBounds = liveDrawing.bounds
        } else if let drawingData,
                  let persistedDrawing = try? PKDrawing(data: drawingData) {
            drawingBounds = persistedDrawing.bounds
        } else {
            drawingBounds = .null
        }

        let drawingBottom =
            (drawingBounds.isNull || drawingBounds.isEmpty) ? 0 : drawingBounds.maxY
        let elementsBottom = canvasElements.elements
            .map { $0.effectiveBoundingBox.maxY }
            .max() ?? 0
        let inkDerivedFilledCount = currentNote.pageGeometry.exportPageCount(
            forContentBottom: max(drawingBottom, elementsBottom)
        )
        let filledCount = max(currentNote.pages.count, inkDerivedFilledCount)
        guard filledCount > currentNote.pages.count else { return }

        for order in currentNote.pages.count..<filledCount {
            currentNote.pages.append(Self.blankPage(order: order))
        }
        note = currentNote
    }

    @discardableResult
    func movePages(source: IndexSet, to destination: Int) -> Bool {
        guard let canvasView = canvasElements.canvasReference?.canvasView,
              !canvasView.isZooming,
              (canvasView as? PagedCanvasView)?.isAnimatingZoomSnap != true else {
            return false
        }

        let pageCountBeforeMaterializing = note?.pages.count ?? 0
        materializePagesForFilledBands()
        guard let currentNote = note else { return false }

        let validSource = IndexSet(
            source.filter { currentNote.pages.indices.contains($0) }
        )
        guard !validSource.isEmpty else {
            if currentNote.pages.count > pageCountBeforeMaterializing {
                noteWasEdited()
            }
            return false
        }

        let clampedDestination = min(max(destination, 0), currentNote.pages.count)
        let permutation = PageBandAssignment.permutation(
            count: currentNote.pages.count,
            moving: validSource,
            to: clampedDestination
        )
        let result = PageReorderer.movePages(
            source: validSource,
            to: clampedDestination,
            drawing: canvasView.drawing,
            elements: canvasElements.elements,
            pages: currentNote.pages,
            geometry: currentNote.pageGeometry
        )

        pendingPageMutationSave =
            currentNote.pages.count > pageCountBeforeMaterializing
            || permutation != Array(0..<currentNote.pages.count)
        defer { pendingPageMutationSave = false }

        canvasElements.performTransaction("Reorder Pages") {
            canvasElements.mutateDrawing { drawing in
                drawing = result.drawing
            }
            canvasElements.replaceAllElements(result.elements)
            note?.pages = result.pages
        }

        if let firstMovedPage = validSource.first {
            onScrollToPage?(permutation[firstMovedPage])
        }
        return true
    }

    @discardableResult
    func deletePage(at index: Int) -> Bool {
        guard let canvasView = canvasElements.canvasReference?.canvasView,
              !canvasView.isZooming,
              (canvasView as? PagedCanvasView)?.isAnimatingZoomSnap != true else {
            return false
        }

        materializePagesForFilledBands()
        guard let currentNote = note else { return false }
        guard currentNote.pages.indices.contains(index),
              currentNote.pages.count > 1 else {
            return false
        }

        pendingPageMutationSave = true
        defer { pendingPageMutationSave = false }

        let result = PageDeleter.deletePage(
            at: index,
            drawing: canvasView.drawing,
            elements: canvasElements.elements,
            pages: currentNote.pages,
            geometry: currentNote.pageGeometry
        )

        canvasElements.performTransaction("Delete Page") {
            canvasElements.mutateDrawing { $0 = result.drawing }
            canvasElements.replaceAllElements(result.elements)
            note?.pages = result.pages
        }

        onScrollToPage?(min(index, (note?.pages.count ?? 1) - 1))
        return true
    }

    func addPageAtEnd() {
        guard let canvasView = canvasElements.canvasReference?.canvasView,
              !canvasView.isZooming,
              (canvasView as? PagedCanvasView)?.isAnimatingZoomSnap != true else {
            return
        }

        materializePagesForFilledBands()
        guard let currentNote = note else { return }
        let newPageIndex = currentNote.pages.count

        pendingPageMutationSave = true
        defer { pendingPageMutationSave = false }
        canvasElements.performTransaction("Add Page") {
            note?.pages.append(Self.blankPage(order: newPageIndex))
        }

        onScrollToPage?(newPageIndex)
    }

    @discardableResult
    func importImage(_ data: Data, visibleContentRect: CGRect) async -> UUID? {
        let processed: ImageImportPipeline.ProcessedImage
        do {
            processed = try await ImageImportPipeline.processForStorage(data)
        } catch {
            handle(error)
            return nil
        }

        let assetPath = "assets/\(UUID().uuidString).jpg"
        guard let note else {
            errorMessage = "The note must be loaded before inserting an image."
            return nil
        }

        do {
            try await notes.saveAsset(
                processed.jpegData,
                noteID: note.id,
                relativePath: assetPath
            )
        } catch {
            handle(error)
            return nil
        }

        let longEdge = max(processed.pixelSize.width, processed.pixelSize.height)
        let fittedLongEdge = 0.6 * min(
            visibleContentRect.width,
            visibleContentRect.height
        )
        let scale = min(
            fittedLongEdge / longEdge,
            PageLayout.contentWidth / processed.pixelSize.width
        )
        let fittedSize = CGSize(
            width: processed.pixelSize.width * scale,
            height: processed.pixelSize.height * scale
        )
        let frameX = min(
            max(0, visibleContentRect.midX - fittedSize.width / 2),
            PageLayout.contentWidth - fittedSize.width
        )
        let frameY = max(0, visibleContentRect.midY - fittedSize.height / 2)
        let frame = CanvasRect(
            x: Double(frameX),
            y: Double(frameY),
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
        let elementID = UUID()
        canvasElements.addElement(
            CanvasElement(
                id: elementID,
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
        return elementID
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

    @discardableResult
    func flushPendingSave() async -> Bool {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        pendingSaveToken = nil
        await saveUntilCurrent()
        return savedGeneration == editGeneration
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
                currentNote.layoutVersion = updated.layoutVersion
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

    private func pagesRestored(_ pages: [NotePage]) {
        guard var currentNote = note,
              !Self.pagesEqual(currentNote.pages, pages) else {
            return
        }
        currentNote.pages = pages
        note = currentNote
        noteWasEdited()
    }

    private static func blankPage(order: Int) -> NotePage {
        let pageID = UUID()
        return NotePage(
            id: pageID,
            order: order,
            plainText: "",
            drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
            background: .blank
        )
    }

    private static func pagesEqual(_ lhs: [NotePage], _ rhs: [NotePage]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { lhsPage, rhsPage in
            lhsPage.id == rhsPage.id
                && lhsPage.order == rhsPage.order
                && lhsPage.plainText == rhsPage.plainText
                && lhsPage.drawingAssetPath == rhsPage.drawingAssetPath
                && lhsPage.background == rhsPage.background
                && lhsPage.pdfPage == rhsPage.pdfPage
                && lhsPage.elements == rhsPage.elements
        }
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
            let generationBefore = savedGeneration
            let task = Task { [weak self] in
                guard let self else { return }
                await self.performSaveLoop()
            }
            inFlightSave = task
            await task.value
            inFlightSave = nil
            if savedGeneration == generationBefore {
                return   // save attempt made no progress (error path already set saveState/.unsaved and surfaced the error) — stop retrying; the next edit or flush re-triggers
            }
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
            currentNote.layoutVersion = savedNote.layoutVersion
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

    private func cachePDFDocuments(for note: Note) async {
        let assetPaths = Set(note.pages.compactMap { $0.pdfPage?.assetPath }).sorted()
        var failures: [String: PDFLoadFailureReason] = [:]

        for assetPath in assetPaths {
            let data: Data
            do {
                guard let loadedData = try await notes.loadAsset(
                    noteID: note.id,
                    relativePath: assetPath
                ) else {
                    failures[assetPath] = .missing
                    continue
                }
                data = loadedData
            } catch {
                failures[assetPath] = .loadError(error.localizedDescription)
                continue
            }
            guard let document = PDFDocument(data: data) else {
                failures[assetPath] = .undecodable
                continue
            }
            pdfCache.setDocument(document, forAssetPath: assetPath)
        }

        pdfLoadFailures = failures
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
