import Foundation
import Observation
import PDFKit
import PencilKit
import UIKit
import VellumCore

@MainActor
@Observable
final class NoteScreenModel {
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
    private let textRecognition: NoteTextRecognitionCoordinator
    let noteAsk: any NoteAskProviding
    private let onNoteChanged: @MainActor (Note) -> Void

    private var pendingSaveTask: Task<Void, Never>?
    private var pendingSaveToken: UUID?
    private var autoAnalyzeIdleTask: Task<Void, Never>?
    private var autoAnalyzeIdleToken: UUID?
    private var inFlightAutoAnalyze: Task<Void, Never>?
    private var editGeneration = 0
    private var savedGeneration = 0
    private var inFlightSave: Task<Void, Never>?
    private var drawingDataPendingSave: Data?
    private var autosaveDisabled = false
    private var pendingPageMutationSave = false

    var note: Note? {
        didSet {
            pdfCache.contentWidth = note?.pageGeometry.contentWidth
                ?? PageGeometry.a4.contentWidth
        }
    }
    var drawingData: Data?
    var proposals: [AgentProposal] = []
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
    var isShowingPhotosPicker = false
    var isShowingFileImporter = false
    var selectedEntity: Entity?
    var noteTitles: [UUID: String] = [:]
    var onScrollToPage: ((Int) -> Void)?
    var hasHiddenSelectionStrokes: (() -> Bool)?
    var onPageOrientationChanged: (() -> Void)?
    var onOrientationFlipped: ((CGFloat) -> Void)?

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
        textRecognition = container.textRecognition
        noteAsk = container.noteAsk
        self.onNoteChanged = onNoteChanged
        canvasElements.onElementsChanged = { [weak self] elements in
            self?.elementsChanged(elements)
        }
        canvasElements.pagesProvider = { [weak self] in
            self?.note?.pages ?? []
        }
        canvasElements.noteShapeProvider = { [weak self] in
            guard let note = self?.note else {
                return CanvasElementsStore.NoteShape(
                    portraitAspectRatio: PageLayout.a4AspectRatio,
                    orientation: .portrait
                )
            }
            return CanvasElementsStore.NoteShape(
                portraitAspectRatio: note.pageAspectRatio,
                orientation: note.pageOrientation
            )
        }
        pdfCache.pagesProvider = { [weak self] in
            self?.note?.pages ?? []
        }
        canvasElements.onPagesRestored = { [weak self] pages in
            self?.pagesRestored(pages)
        }
        canvasElements.onNoteShapeRestored = { [weak self] shape in
            self?.noteShapeRestored(shape)
        }
    }

    var title: String {
        get { note?.title ?? "" }
        set {
            guard note?.title != newValue else { return }
            note?.title = newValue
            note?.titleOrigin = .manual
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
                    layoutVersion: loadedNote.layoutVersion,
                    targetContentWidth: loadedNote.pageGeometry.contentWidth
                )
                if migration.didMigrate {
                    drawingChanged(migration.drawing.dataRepresentation())
                    canvasElements.hydrate(migration.elements)
                    elementsChanged(canvasElements.elements)
                }

                guard var currentNote = note else { return }
                currentNote.layoutVersion = Note.currentLayoutVersion
                note = currentNote
                noteWasEdited()
            }
            isShowingBackgroundChooser = offersBackgroundChooser
            Task { [weak self] in
                guard let self else { return }
                await self.autoAnalyzeIfNeeded()
            }
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
    func setPageOrientation(_ orientation: PageOrientation) -> Bool {
        guard let canvasView = canvasElements.canvasReference?.canvasView,
              !canvasView.isZooming,
              (canvasView as? PagedCanvasView)?.isAnimatingZoomSnap != true else {
            return false
        }
        guard hasHiddenSelectionStrokes?() != true,
              pdfBands.isEmpty,
              var currentNote = note,
              currentNote.pageOrientation != orientation else {
            return false
        }

        let visibleCenterContentY = (canvasView as? PagedCanvasView).map { canvas in
            (canvas.contentOffset.y + canvas.bounds.height / 2) / canvas.zoomScale
        }

        pendingPageMutationSave = true
        defer { pendingPageMutationSave = false }
        canvasElements.performTransaction("Rotate Pages") {
            currentNote.pageOrientation = orientation
            note = currentNote
            materializePagesForFilledBands()
        }

        onPageOrientationChanged?()
        if let visibleCenterContentY {
            onOrientationFlipped?(visibleCenterContentY)
        }
        return true
    }

    func orientationWouldPushContentOffPage(to orientation: PageOrientation) -> Bool {
        guard let note else { return false }

        let drawingBounds: CGRect
        if let liveDrawing = canvasElements.canvasReference?.canvasView?.drawing {
            drawingBounds = liveDrawing.bounds
        } else if let drawingData,
                  let persistedDrawing = try? PKDrawing(data: drawingData) {
            drawingBounds = persistedDrawing.bounds
        } else {
            drawingBounds = .null
        }

        let drawingRight =
            (drawingBounds.isNull || drawingBounds.isEmpty) ? 0 : drawingBounds.maxX
        let elementsRight = canvasElements.elements
            .map { $0.effectiveBoundingBox.maxX }
            .max() ?? 0
        let targetWidth = PageGeometry(
            portraitAspectRatio: note.pageAspectRatio,
            orientation: orientation
        ).contentWidth
        return max(drawingRight, elementsRight) > targetWidth
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
    func importImage(
        _ data: Data,
        visibleContentRect: CGRect,
        centeredAt target: CGPoint? = nil
    ) async -> UUID? {
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
        let contentWidth = note.pageGeometry.contentWidth

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
            contentWidth / processed.pixelSize.width
        )
        let fittedSize = CGSize(
            width: processed.pixelSize.width * scale,
            height: processed.pixelSize.height * scale
        )
        let center = target ?? CGPoint(
            x: visibleContentRect.midX,
            y: visibleContentRect.midY
        )
        let frameX = min(
            max(0, center.x - fittedSize.width / 2),
            contentWidth - fittedSize.width
        )
        let frameY = max(0, center.y - fittedSize.height / 2)
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
        canvasElements.finishTextEditingSession(matching: nil)
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        pendingSaveToken = nil
        await saveUntilCurrent()
        return savedGeneration == editGeneration
    }

    func organize() async {
        await flushPendingSave()
        guard !autosaveDisabled, savedGeneration == editGeneration else { return }

        let analyzedTextHash = currentAnalysisText().map {
            AgentStateSidecar.textHash(for: $0)
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            try await performAnalysis()
            if let analyzedTextHash {
                try await saveAgentAnalysisState(textHash: analyzedTextHash)
            }
        } catch {
            handle(error)
        }
    }

    func autoAnalyzeIfNeeded() async {
        // Analysis can persist proposals incrementally, so overlapping triggers join
        // the current work instead of cancelling and replacing it.
        if let inFlightAutoAnalyze {
            await inFlightAutoAnalyze.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performAutoAnalysisIfNeeded()
        }
        inFlightAutoAnalyze = task
        await task.value
        inFlightAutoAnalyze = nil
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
        scheduleIdleAutoAnalyze()
    }

    private func pagesRestored(_ pages: [NotePage]) {
        guard var currentNote = note, currentNote.pages != pages else {
            return
        }
        currentNote.pages = pages
        note = currentNote
        noteWasEdited()
    }

    private func noteShapeRestored(_ shape: CanvasElementsStore.NoteShape) {
        guard var currentNote = note,
              currentNote.pageAspectRatio != shape.portraitAspectRatio
                || currentNote.pageOrientation != shape.orientation else {
            return
        }
        currentNote.pageAspectRatio = shape.portraitAspectRatio
        currentNote.pageOrientation = shape.orientation
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

    private func scheduleIdleAutoAnalyze() {
        autoAnalyzeIdleTask?.cancel()
        let token = UUID()
        autoAnalyzeIdleToken = token
        autoAnalyzeIdleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(120))
            } catch {
                return
            }
            guard let self else { return }
            await self.autoAnalyzeIfNeeded()
            self.clearIdleAutoAnalyzeTask(matching: token)
        }
    }

    private func clearIdleAutoAnalyzeTask(matching token: UUID) {
        guard autoAnalyzeIdleToken == token else { return }
        autoAnalyzeIdleTask = nil
        autoAnalyzeIdleToken = nil
    }

    private func performAutoAnalysisIfNeeded() async {
        guard SettingsKeys.isAutoOrganizeEnabled() else { return }

        await flushPendingSave()
        guard !autosaveDisabled, savedGeneration == editGeneration else { return }

        guard let analysisText = currentAnalysisText(), analysisText.count >= 80 else {
            return
        }

        let textHash = AgentStateSidecar.textHash(for: analysisText)
        let previousState = await loadAgentAnalysisState()
        guard previousState?.lastAnalyzedTextHash != textHash else { return }

        do {
            try await performAnalysis()
            try await saveAgentAnalysisState(textHash: textHash)
        } catch {
            print("WARNING: auto-analyze failed: \(error)")
        }
    }

    private func currentAnalysisText() -> String? {
        note?.pages
            .sorted(by: NotePage.byOrder)
            .map(\.plainText)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadAgentAnalysisState() async -> AgentAnalysisState? {
        do {
            guard let data = try await notes.loadAsset(
                noteID: noteID,
                relativePath: AgentStateSidecar.relativePath
            ) else {
                return nil
            }
            return try? VellumJSONCoding.decoder().decode(
                AgentAnalysisState.self,
                from: data
            )
        } catch {
            print("WARNING: auto-analyze state could not be loaded: \(error)")
            return nil
        }
    }

    private func saveAgentAnalysisState(textHash: String) async throws {
        let state = AgentAnalysisState(
            schemaVersion: AgentStateSidecar.schemaVersion,
            lastAnalyzedTextHash: textHash,
            analyzedAt: Date()
        )
        let data = try VellumJSONCoding.encoder().encode(state)
        try await notes.saveAsset(
            data,
            noteID: noteID,
            relativePath: AgentStateSidecar.relativePath
        )
    }

    private func performAnalysis() async throws {
        _ = try await workspace.requestAnalysis(noteID: noteID)
        proposals = sortedProposals(
            try await workspace.listProposals(noteID: noteID)
        )
        try await refreshRelatedContent()
    }

    private func saveUntilCurrent() async {
        while let inFlight = inFlightSave {
            await inFlight.value
            // Awaiting an already-completed task resumes without suspending, so
            // this loop can starve the creator's continuation (which clears
            // inFlightSave after the same await) and livelock the main actor
            // when two flushes overlap. Yield so the creator runs before the
            // re-check.
            await Task.yield()
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
                if let input = currentRecognitionInput() {
                    textRecognition.noteDidSave(input)
                }
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

extension NoteScreenModel: RecognitionApplying {
    func currentRecognitionInput() -> TextRecognitionInput? {
        guard let note else { return nil }
        return TextRecognitionInput(note: note, drawingData: drawingData)
    }

    func applyRecognitionOutcome(_ outcome: TextRecognitionOutcome) {
        guard var currentNote = note,
              TextRecognitionService.fingerprint(
                  for: TextRecognitionInput(note: currentNote, drawingData: drawingData)
              ) == outcome.fingerprint else {
            return
        }

        var changed = false
        for index in currentNote.pages.indices {
            if let text = outcome.pageTexts[currentNote.pages[index].id],
               currentNote.pages[index].plainText != text {
                currentNote.pages[index].plainText = text
                changed = true
            }
        }

        if currentNote.isEligibleForAutoTitle {
            let orderedPages = currentNote.pages.sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.order < rhs.order
            }
            if let pageText = orderedPages.lazy.compactMap({ page -> String? in
                guard let text = outcome.pageTexts[page.id],
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return text
            }).first {
                let title = TitleSuggestion.firstSentence(from: pageText)
                if !title.isEmpty {
                    currentNote.title = title
                    currentNote.titleOrigin = .auto
                    changed = true
                }
            }
        }

        guard changed else { return }
        note = currentNote
        noteWasEdited()
    }
}
