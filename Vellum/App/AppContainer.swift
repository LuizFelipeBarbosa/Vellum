import Foundation
import VellumCore

struct AppContainer: Sendable {
    let rootDirectory: URL
    let notes: any NoteRepository
    let proposals: any AgentProposalRepository
    let activity: any ActivityRepository
    let agent: any VellumAgent
    let spaces: any SpaceRepository
    let entities: any EntityRepository
    let tasks: any TaskRepository
    let workspace: WorkspaceService
    let graph: KnowledgeGraphService
    let askService: AskService
    let noteAsk: any NoteAskProviding
    let textRecognition: NoteTextRecognitionCoordinator

    @MainActor
    init(
        rootDirectory: URL,
        notes: any NoteRepository,
        proposals: any AgentProposalRepository,
        activity: any ActivityRepository,
        agent: any VellumAgent,
        spaces: any SpaceRepository,
        entities: any EntityRepository,
        tasks: any TaskRepository,
        workspace: WorkspaceService,
        graph: KnowledgeGraphService,
        askService: AskService,
        noteAsk: any NoteAskProviding = KeywordNoteAskProvider()
    ) {
        self.rootDirectory = rootDirectory
        self.notes = notes
        self.proposals = proposals
        self.activity = activity
        self.agent = agent
        self.spaces = spaces
        self.entities = entities
        self.tasks = tasks
        self.workspace = workspace
        self.graph = graph
        self.askService = askService
        self.noteAsk = noteAsk
        textRecognition = NoteTextRecognitionCoordinator(
            service: TextRecognitionService(recognizer: InkTextRecognizer()),
            workspace: workspace,
            notes: notes
        )
    }

    @MainActor
    static func live(rootDirectory: URL) -> AppContainer {
        let notes = FileNoteRepository(rootDirectory: rootDirectory)
        let proposals = FileProposalRepository(rootDirectory: rootDirectory)
        let activity = FileActivityRepository(rootDirectory: rootDirectory)
        let agent = HeuristicVellumAgent()
        let spaces = FileSpaceRepository(rootDirectory: rootDirectory)
        let entities = FileEntityRepository(rootDirectory: rootDirectory)
        let tasks = FileTaskRepository(rootDirectory: rootDirectory)
        let workspace = WorkspaceService(
            notes: notes,
            proposals: proposals,
            activity: activity,
            agent: agent,
            spaces: spaces,
            entities: entities,
            tasks: tasks
        )
        let graph = KnowledgeGraphService(notes: notes, spaces: spaces, entities: entities)
        let askService = AskService(
            notes: notes,
            answerer: HeuristicAskAnswerer(),
            activity: activity
        )
        // NoteAskFlowUITests passes this argument to force deterministic keyword answers.
        // Release builds compile out the hook and always use Foundation Models with fallback.
        #if DEBUG
        let noteAsk: any NoteAskProviding
        if ProcessInfo.processInfo.arguments.contains("-vellum-heuristic-ai") {
            noteAsk = KeywordNoteAskProvider()
        } else {
            noteAsk = FoundationModelsNoteAskProvider(fallback: KeywordNoteAskProvider())
        }
        #else
        let noteAsk: any NoteAskProviding = FoundationModelsNoteAskProvider(
            fallback: KeywordNoteAskProvider()
        )
        #endif

        return AppContainer(
            rootDirectory: rootDirectory,
            notes: notes,
            proposals: proposals,
            activity: activity,
            agent: agent,
            spaces: spaces,
            entities: entities,
            tasks: tasks,
            workspace: workspace,
            graph: graph,
            askService: askService,
            noteAsk: noteAsk
        )
    }

    func seedIfNeeded() async -> Bool {
        let seeder = WorkspaceSeeder(
            rootDirectory: rootDirectory,
            notes: notes,
            spaces: spaces,
            entities: entities,
            tasks: tasks,
            activity: activity
        )
        do {
            return try await seeder.seedIfNeeded()
        } catch {
            print("WARNING: workspace seeding failed: \(error)")
            return false
        }
    }
}
