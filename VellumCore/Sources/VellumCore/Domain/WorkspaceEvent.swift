import Foundation

public struct WorkspaceEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let noteRevision: Int
    public let createdAt: Date
    public let kind: WorkspaceEventKind

    public init(
        id: UUID,
        noteID: UUID,
        noteRevision: Int,
        createdAt: Date,
        kind: WorkspaceEventKind
    ) {
        self.id = id
        self.noteID = noteID
        self.noteRevision = noteRevision
        self.createdAt = createdAt
        self.kind = kind
    }
}

public enum WorkspaceEventKind: String, Codable, Sendable {
    case noteCreated
    case noteUpdated
    case analysisRequested
}
