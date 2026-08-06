import Foundation

public struct NoteAskTurn: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let question: String
    public var answerText: String
    public var citations: [Citation]
    public var isComplete: Bool

    public init(
        id: UUID = UUID(),
        question: String,
        answerText: String = "",
        citations: [Citation] = [],
        isComplete: Bool = false
    ) {
        self.id = id
        self.question = question
        self.answerText = answerText
        self.citations = citations
        self.isComplete = isComplete
    }
}

public enum NoteAskAvailability: Sendable, Equatable {
    case available
    case fallback(reason: String)
}

public enum NoteAskStreamEvent: Sendable, Equatable {
    case citations([Citation])
    case partial(String)
    case done
}
