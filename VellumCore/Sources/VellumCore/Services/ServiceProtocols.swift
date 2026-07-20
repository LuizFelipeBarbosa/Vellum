import Foundation

public protocol NoteRepository: Sendable {
    func listNotes() async throws -> [Note]
    func createNote(title: String) async throws -> Note
    func insertNote(_ note: Note) async throws
    func loadNote(id: UUID) async throws -> Note
    func saveNote(_ note: Note) async throws
    func deleteNote(id: UUID) async throws
    func loadAsset(noteID: UUID, relativePath: String) async throws -> Data?
    func assetSize(noteID: UUID, relativePath: String) async throws -> Int?
    func saveAsset(_ data: Data, noteID: UUID, relativePath: String) async throws
}

public protocol SpaceRepository: Sendable {
    func list() async throws -> [Space]
    func save(_ space: Space) async throws
    func delete(id: UUID) async throws
}

public protocol EntityRepository: Sendable {
    func list() async throws -> [Entity]
    func save(_ entity: Entity) async throws
    func delete(id: UUID) async throws
}

public protocol TaskRepository: Sendable {
    func list() async throws -> [TaskItem]
    func save(_ task: TaskItem) async throws
    func delete(id: UUID) async throws
}

public protocol VellumAgent: Sendable {
    func analyze(event: WorkspaceEvent, context: AgentContext) async throws -> [AgentProposal]
}

public protocol AgentProposalRepository: Sendable {
    func list(noteID: UUID) async throws -> [AgentProposal]
    func load(id: UUID) async throws -> AgentProposal
    func save(_ proposal: AgentProposal) async throws
    func update(_ proposal: AgentProposal) async throws
}

public protocol ActivityRepository: Sendable {
    func append(_ event: ActivityEvent) async throws
    func list(noteID: UUID?) async throws -> [ActivityEvent]
}

public protocol NoteSyncing: Sendable {
    func enqueue(noteID: UUID) async
    func synchronize() async throws
}

public protocol SourceImporting: Sendable {
    func importSource(from url: URL) async throws -> ImportedSource
}

public protocol KnowledgeExporting: Sendable {
    func exportWorkspace() async throws -> URL
}
