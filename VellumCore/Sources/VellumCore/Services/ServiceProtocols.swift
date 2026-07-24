import Foundation

public enum NoteListScope: Sendable {
    case active, trashed, all
}

public protocol NoteRepository: Sendable {
    func listNotes(scope: NoteListScope) async throws -> [Note]
    func unsupportedNotes() async throws -> [UnsupportedNotePackage]
    func createNote(title: String) async throws -> Note
    func insertNote(_ note: Note) async throws
    func importNote(_ note: Note, assets: [(relativePath: String, data: Data)]) async throws
    func loadNote(id: UUID) async throws -> Note
    func saveNote(_ note: Note) async throws
    func deleteNote(id: UUID) async throws
    @discardableResult
    func purgeNote(id: UUID) async throws -> Bool
    func loadAsset(noteID: UUID, relativePath: String) async throws -> Data?
    func assetSize(noteID: UUID, relativePath: String) async throws -> Int?
    func saveAsset(_ data: Data, noteID: UUID, relativePath: String) async throws
    func deleteAsset(noteID: UUID, relativePath: String) async throws
    func purgeUnreferencedAssets(noteID: UUID) async throws
}

public extension NoteRepository {
    func listNotes() async throws -> [Note] {
        try await listNotes(scope: .active)
    }

    func unsupportedNotes() async throws -> [UnsupportedNotePackage] {
        []
    }
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
