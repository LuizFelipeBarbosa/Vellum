import Foundation

public actor FileProposalRepository: AgentProposalRepository {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func list(noteID: UUID) async throws -> [AgentProposal] {
        let package = FilePersistence.packageURL(rootDirectory: rootDirectory, noteID: noteID)
        let directory = package.appendingPathComponent("proposals", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }
        } catch {
            throw VellumError.persistenceFailure("Could not list proposals for note \(noteID.uuidString): \(error.localizedDescription)")
        }

        do {
            let proposals = try files.map { file in
                try FilePersistence.decoder().decode(AgentProposal.self, from: Data(contentsOf: file))
            }
            return proposals.sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
        } catch {
            throw VellumError.persistenceFailure("Could not decode proposals for note \(noteID.uuidString): \(error.localizedDescription)")
        }
    }

    public func load(id: UUID) async throws -> AgentProposal {
        for package in try FilePersistence.packageDirectories(rootDirectory: rootDirectory) {
            let file = package
                .appendingPathComponent("proposals", isDirectory: true)
                .appendingPathComponent("\(id.uuidString).json")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                return try FilePersistence.decoder().decode(AgentProposal.self, from: Data(contentsOf: file))
            } catch {
                throw VellumError.persistenceFailure("Could not decode proposal \(id.uuidString): \(error.localizedDescription)")
            }
        }
        throw VellumError.proposalNotFound(id)
    }

    public func save(_ proposal: AgentProposal) async throws {
        _ = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: proposal.noteID)
        let relativePath = "proposals/\(proposal.id.uuidString).json"
        let file = try FilePersistence.validatedAssetURL(
            rootDirectory: rootDirectory,
            noteID: proposal.noteID,
            relativePath: relativePath
        )
        try FilePersistence.write(proposal, to: file)
    }

    public func update(_ proposal: AgentProposal) async throws {
        _ = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: proposal.noteID)
        let relativePath = "proposals/\(proposal.id.uuidString).json"
        let file = try FilePersistence.validatedAssetURL(
            rootDirectory: rootDirectory,
            noteID: proposal.noteID,
            relativePath: relativePath
        )
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw VellumError.proposalNotFound(proposal.id)
        }
        try FilePersistence.write(proposal, to: file)
    }
}
