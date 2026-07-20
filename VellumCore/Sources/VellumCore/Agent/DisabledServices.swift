import Foundation

public struct DisabledNoteSync: NoteSyncing, Sendable {
    public init() {}

    public func enqueue(noteID: UUID) async {}

    public func synchronize() async throws {
        throw VellumError.featureUnavailable("sync")
    }
}

public struct DisabledSourceImporter: SourceImporting, Sendable {
    public init() {}

    public func importSource(from url: URL) async throws -> ImportedSource {
        throw VellumError.featureUnavailable("import")
    }
}

public struct DisabledKnowledgeExporter: KnowledgeExporting, Sendable {
    public init() {}

    public func exportWorkspace() async throws -> URL {
        throw VellumError.featureUnavailable("export")
    }
}
