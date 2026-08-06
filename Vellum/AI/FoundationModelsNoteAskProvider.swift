import Foundation
import FoundationModels
import VellumCore

struct FoundationModelsNoteAskProvider: NoteAskProviding {
    let fallback: any NoteAskProviding

    func availability() async -> NoteAskAvailability {
        if #available(iOS 26.0, *) {
            return AppleIntelligence.availability()
        }
        return .fallback(reason: "Requires iOS 26 or later")
    }

    func makeSession(source: AskSource) async -> any NoteAskSession {
        let currentAvailability = await availability()
        if #available(iOS 26.0, *), currentAvailability == .available {
            return FoundationModelsNoteAskSession(source: source)
        }
        return await fallback.makeSession(source: source)
    }
}

@available(iOS 26.0, *)
actor FoundationModelsNoteAskSession: NoteAskSession {
    private struct TurnContext: Sendable {
        let prompt: String
        let includedPages: [AskPage]
    }

    private struct CompletedTurn: Sendable {
        let question: String
        let answer: String
    }

    private static let wholeNoteCharacterBudget = 9_000
    private static let retrievalCharacterBudget = 6_000
    private static let responseTokenBudget = 700
    private static let safetyResponse = "I can't answer that here."

    private let source: AskSource
    private let contextPacker = NoteAskContextPacker()
    private let wholeNoteContext: NoteAskContextPacker.PackedContext?
    private let baseInstructions: String
    private var session: LanguageModelSession
    private var lastCompletedTurn: CompletedTurn?
    private var turnInProgress = false
    private var turnWaiters: [CheckedContinuation<Void, Never>] = []

    init(source: AskSource) {
        self.source = source

        let wholeNoteContext = NoteAskContextPacker().packWholeNote(
            source,
            charBudget: Self.wholeNoteCharacterBudget
        )
        self.wholeNoteContext = wholeNoteContext

        var instructions = Self.roleInstructions(for: source.title)
        if let wholeNoteContext {
            instructions += "\n\nNote text:\n\(wholeNoteContext.text)"
        }
        self.baseInstructions = instructions
        self.session = LanguageModelSession(instructions: instructions)
    }

    nonisolated func ask(
        _ question: String
    ) -> AsyncThrowingStream<NoteAskStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.runAsk(question, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func summarize() async throws -> String {
        let joinedText = source.pages.map(\.plainText).joined(separator: "\n\n")
        let noteText = contextPacker.packWholeNote(
            source,
            charBudget: Self.wholeNoteCharacterBudget
        )?.text ?? TokenBudget.truncateHeadAndTail(
            joinedText,
            charBudget: Self.wholeNoteCharacterBudget
        )

        let summarySession = LanguageModelSession(
            instructions: Self.roleInstructions(for: source.title)
        )
        let response = try await summarySession.respond(
            to: """
            Note text:
            \(noteText)

            Summarize this note in 3-5 short bullet points.
            """
        )
        return response.content
    }

    private func runAsk(
        _ question: String,
        continuation: AsyncThrowingStream<NoteAskStreamEvent, Error>.Continuation
    ) async {
        await acquireTurn()
        defer { releaseTurn() }

        do {
            try Task.checkCancellation()
            while session.isResponding {
                try Task.checkCancellation()
                await Task.yield()
            }

            let turnContext = makeTurnContext(
                question: question,
                retrievalCharacterBudget: Self.retrievalCharacterBudget
            )
            continuation.yield(.citations(citations(for: turnContext.includedPages)))

            let answer = try await answer(
                question: question,
                turnContext: turnContext,
                continuation: continuation
            )
            lastCompletedTurn = CompletedTurn(question: question, answer: answer)
            continuation.yield(.done)
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func answer(
        question: String,
        turnContext: TurnContext,
        continuation: AsyncThrowingStream<NoteAskStreamEvent, Error>.Continuation
    ) async throws -> String {
        do {
            return try await streamAnswer(
                prompt: turnContext.prompt,
                continuation: continuation
            )
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                rebuildSession()
                let retryContext = makeTurnContext(
                    question: question,
                    retrievalCharacterBudget: Self.retrievalCharacterBudget / 2
                )
                do {
                    return try await streamAnswer(
                        prompt: retryContext.prompt,
                        continuation: continuation
                    )
                } catch let retryError as LanguageModelSession.GenerationError {
                    switch retryError {
                    case .guardrailViolation, .refusal:
                        continuation.yield(.partial(Self.safetyResponse))
                        return Self.safetyResponse
                    default:
                        throw retryError
                    }
                }
            case .guardrailViolation, .refusal:
                continuation.yield(.partial(Self.safetyResponse))
                return Self.safetyResponse
            default:
                throw error
            }
        }
    }

    private func streamAnswer(
        prompt: String,
        continuation: AsyncThrowingStream<NoteAskStreamEvent, Error>.Continuation
    ) async throws -> String {
        var cumulativeAnswer = ""
        let stream = session.streamResponse(
            to: prompt,
            options: GenerationOptions(maximumResponseTokens: Self.responseTokenBudget)
        )
        for try await snapshot in stream {
            try Task.checkCancellation()
            cumulativeAnswer = snapshot.content
            continuation.yield(.partial(cumulativeAnswer))
        }
        return cumulativeAnswer
    }

    private func makeTurnContext(
        question: String,
        retrievalCharacterBudget: Int
    ) -> TurnContext {
        if let wholeNoteContext {
            return TurnContext(
                prompt: "Question:\n\(question)",
                includedPages: wholeNoteContext.includedPages
            )
        }

        let packedContext = contextPacker.packForQuestion(
            question,
            source: source,
            charBudget: retrievalCharacterBudget
        )
        return TurnContext(
            prompt: """
            Relevant note text:
            \(packedContext.text)

            Question:
            \(question)
            """,
            includedPages: packedContext.includedPages
        )
    }

    private func rebuildSession() {
        var instructions = baseInstructions
        if let lastCompletedTurn {
            let recentConversation = TokenBudget.truncateHeadAndTail(
                "Question: \(lastCompletedTurn.question)\nAnswer: \(lastCompletedTurn.answer)",
                charBudget: 500
            )
            instructions += "\n\nRecent conversation:\n\(recentConversation)"
        }
        session = LanguageModelSession(instructions: instructions)
    }

    private func citations(for pages: [AskPage]) -> [Citation] {
        pages.enumerated().map { offset, page in
            let pageText = page.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let excerpt = String(pageText.prefix(80))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Citation(
                id: UUID(),
                index: offset + 1,
                noteID: source.noteID,
                pageID: page.pageID,
                noteTitle: source.title,
                noteType: source.noteType,
                excerpt: excerpt
            )
        }
    }

    private func acquireTurn() async {
        guard turnInProgress else {
            turnInProgress = true
            return
        }

        await withCheckedContinuation { continuation in
            turnWaiters.append(continuation)
        }
    }

    private func releaseTurn() {
        guard !turnWaiters.isEmpty else {
            turnInProgress = false
            return
        }
        turnWaiters.removeFirst().resume()
    }

    private static func roleInstructions(for title: String) -> String {
        "You answer questions about one handwritten note titled '\(title)'. "
            + "Answer only from the provided note text. "
            + "If the note does not contain the answer, say so plainly. Be concise."
    }
}
