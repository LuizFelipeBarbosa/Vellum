import Foundation
import Observation
import VellumCore

@MainActor
@Observable
final class NoteAskScreenModel: Identifiable {
    enum Phase: Equatable {
        case idle, streaming, error(String)
    }

    // Identity for .sheet(item:) presentation.
    let id = UUID()

    private let note: Note
    private let provider: any NoteAskProviding
    private var session: (any NoteAskSession)?
    private var inFlightTask: Task<Void, Never>?

    var turns: [NoteAskTurn] = []
    var inputText = ""
    var availability: NoteAskAvailability = .available
    var summary: String?
    var phase: Phase = .idle

    init(note: Note, provider: any NoteAskProviding) {
        self.note = note
        self.provider = provider
    }

    func start() async {
        let availability = await provider.availability()
        guard !Task.isCancelled else { return }
        self.availability = availability

        let source = AskSource(
            noteID: note.id,
            title: note.title,
            noteType: note.noteType,
            pages: note.pages
                .sorted(by: NotePage.byOrder)
                .filter {
                    !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .map { AskPage(pageID: $0.id, plainText: $0.plainText) }
        )
        let session = await provider.makeSession(source: source)
        guard !Task.isCancelled else { return }
        self.session = session
    }

    func ask() {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, phase != .streaming, let session else { return }

        inFlightTask?.cancel()
        let turn = NoteAskTurn(question: question)
        turns.append(turn)
        inputText = ""
        phase = .streaming

        inFlightTask = Task { [weak self] in
            guard let self else { return }

            do {
                for try await event in session.ask(question) {
                    guard !Task.isCancelled else { return }
                    guard let turnIndex = self.turns.firstIndex(where: { $0.id == turn.id }) else {
                        return
                    }

                    switch event {
                    case .citations(let citations):
                        self.turns[turnIndex].citations = citations
                    case .partial(let text):
                        self.turns[turnIndex].answerText = text
                    case .done:
                        self.turns[turnIndex].isComplete = true
                        self.phase = .idle
                        return
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard let turnIndex = self.turns.firstIndex(where: { $0.id == turn.id }) else {
                    return
                }
                self.turns[turnIndex].isComplete = true
                self.phase = .error(error.localizedDescription)
            }
        }
    }

    func summarize() {
        guard phase != .streaming, let session else { return }

        inFlightTask?.cancel()
        phase = .streaming
        inFlightTask = Task { [weak self] in
            guard let self else { return }

            do {
                let summary = try await session.summarize()
                guard !Task.isCancelled else { return }
                self.summary = summary
                self.phase = .idle
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .error(error.localizedDescription)
            }
        }
    }

    func cancel() {
        inFlightTask?.cancel()
        inFlightTask = nil
    }
}
