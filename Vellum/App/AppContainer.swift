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
            askService: askService
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
