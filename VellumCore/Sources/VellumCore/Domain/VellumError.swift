import Foundation

public enum VellumError: Error, Equatable, Sendable, LocalizedError {
    case noteNotFound(UUID)
    case corruptManifest(UUID)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case invalidAssetPath(String)
    case staleProposal(UUID)
    case proposalNotFound(UUID)
    case featureUnavailable(String)
    case persistenceFailure(String)

    public var errorDescription: String? {
        switch self {
        case .noteNotFound(let id):
            "Note \(id.uuidString) was not found."
        case .corruptManifest(let id):
            "The manifest for note \(id.uuidString) is corrupt."
        case .unsupportedSchemaVersion(let found, let supported):
            "Schema version \(found) is unsupported; this version supports up to \(supported)."
        case .invalidAssetPath(let path):
            "The asset path '\(path)' is invalid. Use a relative path inside the note package."
        case .staleProposal(let id):
            "Proposal \(id.uuidString) is stale. Request a new analysis before accepting it."
        case .proposalNotFound(let id):
            "Proposal \(id.uuidString) was not found."
        case .featureUnavailable(let feature):
            "The \(feature) feature is unavailable."
        case .persistenceFailure(let message):
            "Persistence failed: \(message)"
        }
    }
}
