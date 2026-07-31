import Foundation
import Observation
import SwiftUI
import VellumCore

enum AppScreen: Hashable {
    case library, graph, ask, trash
    case note
}

enum PanePlacement {
    case replaceFocused
    case replacePane(id: UUID)
    case newColumn(at: Int?)
    case stackInColumn(column: Int, at: Int?)
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let actionLabel: String?
    let action: (@MainActor () -> Void)?

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

@MainActor
@Observable
final class VellumAppModel {
    let container: AppContainer
    let library: LibraryScreenModel
    let graphScreen: GraphScreenModel
    let askScreen: AskScreenModel
    let trashScreen: TrashScreenModel
    let toolPreferences: ToolPreferencesStore
    let split = NoteSplitState()
    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "vellum.appearanceMode")
        }
    }
    var screen: AppScreen {
        didSet {
            guard screen == .library else { return }
            Task { [weak self] in
                guard let self else { return }
                await self.library.refresh()
                await self.refreshStats()
            }
        }
    }
    var currentNote: NoteScreenModel? { split.focusedPane?.noteModel }
    var toast: Toast?
    var showAgent = true
    var noteCount = 0
    var openTaskCount = 0
    var trashCount = 0
    var spaceListings: [SpaceListing] = []
    var activityMessage = "No recent activity"
    var activityCount = 0

    private var toastTask: Task<Void, Never>?
    private var askNavigationTask: Task<Void, Never>?
    private var openingNoteIDs: Set<UUID> = []
    private var lastSplitContainerSize: CGSize = .zero
    private var resizeOverflowTask: Task<Void, Never>?
    private var didBootstrap = false

    #if DEBUG
    private let debugAskQuestion: String?
    private let debugAutoOpenMostRecentNote: Bool
    private let debugSplitPaneCount: Int?
    private let debugSplitGridRows: [Int]?
    #endif

    init(
        container: AppContainer,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        toolPreferences: ToolPreferencesStore = ToolPreferencesStore()
    ) {
        self.container = container
        self.toolPreferences = toolPreferences
        appearanceMode = AppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: "vellum.appearanceMode") ?? ""
        ) ?? .system
        library = LibraryScreenModel(workspace: container.workspace)
        graphScreen = GraphScreenModel(container: container)
        askScreen = AskScreenModel(container: container)
        trashScreen = TrashScreenModel(workspace: container.workspace)
        #if DEBUG
        if let flagIndex = arguments.firstIndex(of: "-askQuestion"),
           arguments.indices.contains(flagIndex + 1) {
            debugAskQuestion = arguments[flagIndex + 1]
        } else {
            debugAskQuestion = nil
        }
        debugAutoOpenMostRecentNote = arguments.contains("-vellum-auto-open-note")
        if let flagIndex = arguments.firstIndex(of: "-vellum-split-panes"),
           arguments.indices.contains(flagIndex + 1),
           let count = Int(arguments[flagIndex + 1]) {
            debugSplitPaneCount = count
        } else {
            debugSplitPaneCount = nil
        }
        if let flagIndex = arguments.firstIndex(of: "-vellum-split-grid"),
           arguments.indices.contains(flagIndex + 1) {
            let components = arguments[flagIndex + 1]
                .split(separator: ",", omittingEmptySubsequences: false)
            let rowCounts = components
                .compactMap { Int($0) }
            debugSplitGridRows = rowCounts.count == components.count
                && !rowCounts.isEmpty
                && rowCounts.allSatisfy { $0 > 0 }
                ? rowCounts
                : []
        } else {
            debugSplitGridRows = nil
        }
        #endif
        if let flagIndex = arguments.firstIndex(of: "-prototypeStartView"),
           arguments.indices.contains(flagIndex + 1) {
            screen = switch arguments[flagIndex + 1] {
            case "library": .library
            case "canvas": .note
            case "graph": .graph
            case "ask": .ask
            default: .library
            }
        } else {
            screen = .library
        }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        _ = await container.seedIfNeeded()
        await library.refresh()
        await graphScreen.refresh()

        if case .note = screen {
            if let noteID = library.summaries.first?.id {
                await openNote(noteID)
            } else {
                screen = .library
            }
        }

        #if DEBUG
        if let debugSplitGridRows {
            let notes = library.summaries.sorted { $0.updatedAt > $1.updatedAt }
            var noteIterator = notes.makeIterator()

            for (columnIndex, rowCount) in debugSplitGridRows.enumerated() {
                guard let firstNote = noteIterator.next() else { break }
                if columnIndex == 0 {
                    await openNote(firstNote.id)
                } else {
                    await openNote(
                        firstNote.id,
                        placement: .newColumn(at: nil)
                    )
                }

                for _ in 1..<rowCount {
                    guard let note = noteIterator.next() else { break }
                    await openNote(
                        note.id,
                        placement: .stackInColumn(
                            column: columnIndex,
                            at: nil
                        )
                    )
                }
            }
        } else if let debugSplitPaneCount, debugSplitPaneCount > 0 {
            let notes = library.summaries.sorted { $0.updatedAt > $1.updatedAt }
            if let mostRecentNote = notes.first {
                await openNote(mostRecentNote.id)
            }
            for note in notes.dropFirst().prefix(debugSplitPaneCount - 1) {
                await openNote(note.id, placement: .newColumn(at: nil))
            }
        }

        if debugSplitGridRows == nil,
           debugSplitPaneCount == nil,
           debugAutoOpenMostRecentNote,
           let note = library.summaries.max(by: { $0.updatedAt < $1.updatedAt }) {
            await openNote(note.id)
        }
        #endif

        await refreshStats()
        await askScreen.loadSuggestions()

        #if DEBUG
        if let debugAskQuestion {
            askScreen.ask(debugAskQuestion)
        }
        #endif
    }

    var activityLine: String {
        "\(activityMessage) · \(activityCount) recent — review"
    }

    func refreshStats() async {
        do {
            noteCount = library.summaries.count
            spaceListings = library.spaces
            openTaskCount = try await container.workspace.listTasks().count { !$0.isDone }
            trashCount = try await container.workspace.listTrashedNotes().count

            let events = try await container.workspace.activity(noteID: nil)
            let digest = try await container.workspace.activityDigest(
                since: Date().addingTimeInterval(-24 * 3600)
            )
            let includedKinds: Set<ActivityKind> = [
                .noteFiledToSpace,
                .notesLinked,
                .taskExtracted,
                .entityExtracted,
                .proposalAccepted,
                .workspaceSeeded,
            ]
            activityMessage = events.last(where: { includedKinds.contains($0.kind) })?.message
                ?? "No recent activity"
            activityCount = digest.totalAgentActions
        } catch {
            library.errorMessage = error.localizedDescription
        }
    }

    func navigate(to newScreen: AppScreen) async {
        if newScreen == .note {
            if split.panes.isEmpty {
                if let firstNoteID = library.summaries.first?.id {
                    await openNote(firstNoteID)
                } else {
                    screen = .library
                }
            } else {
                screen = .note
            }
            return
        }

        if case .note = screen {
            // Panes hold live canvases and undo stacks; restoring splits across navigation is out
            // of scope for v1.
            await split.closeAll()
        }

        if screen != newScreen {
            screen = newScreen
        }
        if newScreen == .graph {
            await graphScreen.refresh()
        }
        if newScreen == .trash {
            await trashScreen.refresh()
        }
    }

    func openNote(
        _ id: UUID,
        isNewlyCreated: Bool = false,
        placement: PanePlacement = .replaceFocused
    ) async {
        guard !openingNoteIDs.contains(id) else { return }
        openingNoteIDs.insert(id)
        defer { openingNoteIDs.remove(id) }

        do {
            let note = try await container.workspace.loadNote(id: id)
            if note.isTrashed {
                showToast("This note is in the Trash")
                return
            }
        } catch {
            library.errorMessage = error.localizedDescription
            return
        }

        if let existingPane = split.pane(for: id) {
            split.focus(existingPane.id)
            screen = .note
            return
        }

        let noteModel = NoteScreenModel(
            noteID: id,
            container: container,
            offersBackgroundChooser: isNewlyCreated,
            onNoteChanged: { [weak self] _ in
                Task { [weak self] in
                    guard let self else { return }
                    await self.library.refresh()
                    await self.refreshStats()
                }
            }
        )
        let newPane = NotePane(noteModel: noteModel)

        switch placement {
        case .replaceFocused:
            if let focusedPane = split.focusedPane {
                await focusedPane.noteModel.flushPendingSave()
                split.replacePane(id: focusedPane.id, with: newPane)
            } else {
                split.insertColumn(with: newPane, at: 0)
            }
        case .replacePane(let paneID):
            if let pane = split.panes.first(where: { $0.id == paneID }) {
                await pane.noteModel.flushPendingSave()
            }
            if split.panes.contains(where: { $0.id == paneID }) {
                split.replacePane(id: paneID, with: newPane)
            } else if let focusedPane = split.focusedPane {
                await focusedPane.noteModel.flushPendingSave()
                split.replacePane(id: focusedPane.id, with: newPane)
            } else {
                split.insertColumn(with: newPane, at: 0)
            }
        case .newColumn(let index):
            split.insertColumn(with: newPane, at: index)
        case .stackInColumn(let column, let row):
            split.stackPane(newPane, inColumn: column, at: row)
        }

        screen = .note
    }

    func handleSplitContainerResize(_ size: CGSize) {
        lastSplitContainerSize = size
        resizeOverflowTask?.cancel()
        resizeOverflowTask = nil
        reclampSplitGrid()
    }

    func reclampSplitGrid() {
        guard lastSplitContainerSize != .zero, !split.columns.isEmpty else { return }
        // The live-state eviction loop converges on its own; restarting it here would
        // reset its count and make removals crawl behind repeated debounce delays.
        guard resizeOverflowTask == nil else { return }

        let result = SplitGridPolicy.reclamped(
            split.gridSnapshot,
            containerSize: lastSplitContainerSize
        )
        guard !result.overflow.isEmpty else {
            resizeOverflowTask = nil
            split.applyGrid(result.grid)
            return
        }

        resizeOverflowTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }

            var closedPaneCount = 0
            while true {
                guard !Task.isCancelled else { return }

                let result = SplitGridPolicy.reclamped(
                    self.split.gridSnapshot,
                    containerSize: self.lastSplitContainerSize
                )
                guard !result.overflow.isEmpty else {
                    self.split.applyGrid(result.grid)
                    break
                }

                let overflowPaneIDs = result.overflow.compactMap { index -> UUID? in
                    guard self.split.columns.indices.contains(index.column),
                          self.split.columns[index.column].panes.indices.contains(index.row)
                    else {
                        return nil
                    }
                    return self.split.columns[index.column].panes[index.row].id
                }

                for paneID in overflowPaneIDs {
                    guard !Task.isCancelled else { return }
                    guard let pane = self.split.panes.first(
                        where: { $0.id == paneID }
                    ) else {
                        continue
                    }
                    await pane.noteModel.flushPendingSave()
                    guard !Task.isCancelled else { return }
                    guard self.split.panes.contains(
                        where: { $0.id == paneID }
                    ) else {
                        continue
                    }
                    self.split.removePane(id: paneID)
                    closedPaneCount += 1
                }
            }

            if closedPaneCount > 0 {
                self.showToast(
                    "Closed \(closedPaneCount) pane\(closedPaneCount == 1 ? "" : "s") to fit"
                )
            }
            self.resizeOverflowTask = nil
        }
    }

    func closePane(_ paneID: UUID) async {
        if let pane = split.panes.first(where: { $0.id == paneID }) {
            await pane.noteModel.flushPendingSave()
        }
        split.removePane(id: paneID)
        if split.panes.isEmpty {
            await navigate(to: .library)
        }
    }

    func deleteNote(id: UUID) async throws {
        let pane = split.pane(for: id)
        if let pane {
            await pane.noteModel.flushPendingSave()
        }
        try await container.workspace.deleteNote(id: id)
        if let pane {
            split.removePane(id: pane.id)
        }
        if split.panes.isEmpty {
            await navigate(to: .library)
        }
        await library.refresh()
        await refreshStats()
        notifyTrashed([id])
    }

    func createSpace(name: String, color: SpaceColor, parentID: UUID?) async {
        do {
            _ = try await container.workspace.createSpace(
                name: name,
                color: color,
                parentID: parentID
            )
            await library.refresh()
            await refreshStats()
        } catch {
            library.errorMessage = error.localizedDescription
        }
    }

    func deleteSpace(_ id: UUID) async {
        do {
            try await container.workspace.deleteSpace(id: id)
            await library.refresh()
            await refreshStats()
            await trashScreen.refresh()
        } catch {
            library.errorMessage = error.localizedDescription
        }
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        let newToast = Toast(text: message, actionLabel: nil, action: nil)
        toast = newToast
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            guard self?.toast?.id == newToast.id else { return }
            self?.toast = nil
        }
    }

    func showToast(
        _ message: String,
        actionLabel: String,
        action: @escaping @MainActor () -> Void
    ) {
        toastTask?.cancel()
        let newToast = Toast(text: message, actionLabel: actionLabel, action: action)
        toast = newToast
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            guard self?.toast?.id == newToast.id else { return }
            self?.toast = nil
        }
    }

    func notifyTrashed(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let text = ids.count == 1 ? "Moved to Trash" : "Moved \(ids.count) notes to Trash"
        showToast(text, actionLabel: "Undo") { [weak self] in
            guard let self else { return }
            Task {
                try? await self.container.workspace.restoreNotes(ids: ids)
                await self.trashScreen.refresh()
                await self.library.refresh()
                await self.refreshStats()
            }
        }
    }

    func ask(question: String) async {
        await navigate(to: .ask)
        guard !Task.isCancelled else { return }
        askScreen.ask(question)
    }

    func askAbout(_ question: String) {
        askNavigationTask?.cancel()
        askNavigationTask = Task { [weak self] in
            guard let self else { return }
            await self.ask(question: question)
        }
    }

    func goAskIdle() {
        askNavigationTask?.cancel()
        askNavigationTask = Task { [weak self] in
            guard let self else { return }
            await self.navigate(to: .ask)
            guard !Task.isCancelled else { return }
            self.askScreen.reset()
            await self.askScreen.loadSuggestions()
        }
    }
}
