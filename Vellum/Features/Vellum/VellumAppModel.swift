import Foundation
import Observation
import SwiftUI
import VellumCore

enum AppScreen: Hashable {
    case library, graph, ask
    case note(UUID?)
}

@MainActor
@Observable
final class VellumAppModel {
    let container: AppContainer
    let library: LibraryScreenModel
    let graphScreen: GraphScreenModel
    let askScreen: AskScreenModel
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
    var currentNote: NoteScreenModel?
    var toastText: String?
    var showAgent = true
    var noteCount = 0
    var openTaskCount = 0
    var spaceListings: [SpaceListing] = []
    var activityMessage = "No recent activity"
    var activityCount = 0

    private var toastTask: Task<Void, Never>?
    private var askNavigationTask: Task<Void, Never>?
    private var didBootstrap = false

    #if DEBUG
    private let debugAskQuestion: String?
    #endif

    init(container: AppContainer, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.container = container
        library = LibraryScreenModel(workspace: container.workspace)
        graphScreen = GraphScreenModel(container: container)
        askScreen = AskScreenModel(container: container)
        #if DEBUG
        if let flagIndex = arguments.firstIndex(of: "-askQuestion"),
           arguments.indices.contains(flagIndex + 1) {
            debugAskQuestion = arguments[flagIndex + 1]
        } else {
            debugAskQuestion = nil
        }
        #endif
        if let flagIndex = arguments.firstIndex(of: "-prototypeStartView"),
           arguments.indices.contains(flagIndex + 1) {
            screen = switch arguments[flagIndex + 1] {
            case "library": .library
            case "canvas": .note(nil)
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

        if case .note(nil) = screen {
            if let noteID = library.summaries.first?.id {
                await openNote(noteID)
            } else {
                screen = .library
            }
        }

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
        if case .note(let requestedID) = newScreen {
            if let requestedID {
                await openNote(requestedID)
            } else if let firstNoteID = library.summaries.first?.id {
                await openNote(firstNoteID)
            } else {
                if case .note = screen {
                    await currentNote?.flushPendingSave()
                    currentNote = nil
                }
                screen = .library
            }
            return
        }

        if case .note = screen {
            await currentNote?.flushPendingSave()
            currentNote = nil
        }

        if screen != newScreen {
            screen = newScreen
        }
        if newScreen == .graph {
            await graphScreen.refresh()
        }
    }

    func openNote(_ id: UUID) async {
        await currentNote?.flushPendingSave()
        currentNote = nil

        let noteModel = NoteScreenModel(
            noteID: id,
            container: container,
            onNoteChanged: { [weak self] _ in
                Task { [weak self] in
                    guard let self else { return }
                    await self.library.refresh()
                    await self.refreshStats()
                }
            }
        )
        currentNote = noteModel
        screen = .note(id)
    }

    func deleteCurrentNote(id: UUID) async throws {
        await currentNote?.flushPendingSave()
        try await container.workspace.deleteNote(id: id)
        currentNote = nil
        await navigate(to: .library)
        await library.refresh()
        await refreshStats()
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        toastText = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toastText = nil
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
