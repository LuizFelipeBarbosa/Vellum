public protocol NoteAskProviding: Sendable {
    func availability() async -> NoteAskAvailability
    func makeSession(source: AskSource) async -> any NoteAskSession
}

public protocol NoteAskSession: Sendable {
    func ask(_ question: String) -> AsyncThrowingStream<NoteAskStreamEvent, Error>
    func summarize() async throws -> String
}
