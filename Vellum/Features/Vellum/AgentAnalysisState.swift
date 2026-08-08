import CryptoKit
import Foundation

struct AgentAnalysisState: Codable, Equatable {
    var schemaVersion: Int
    var lastAnalyzedTextHash: String
    var analyzedAt: Date
}

enum AgentStateSidecar {
    static let relativePath = "derived/agent-state.json"
    static let schemaVersion = 1

    static func textHash(for text: String) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(text.utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
