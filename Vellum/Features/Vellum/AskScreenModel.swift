import Foundation
import Observation
import VellumCore

@MainActor
@Observable
final class AskScreenModel {
    enum AskPhase: Equatable {
        case idle, thinking, answered
    }

    private let container: AppContainer
    private var askTask: Task<Void, Never>?

    var phase: AskPhase = .idle
    var question = ""
    var answer: AskAnswer?
    var inputText = ""
    var suggested: [String] = []
    var askedAt: Date?
    var answeredIn: TimeInterval?
    var errorMessage: String?

    init(container: AppContainer) {
        self.container = container
    }

    func loadSuggestions() async {
        do {
            let suggestions = try await container.askService.suggestedQuestions()
            guard !Task.isCancelled else { return }
            suggested = suggestions
        } catch {
            guard !Task.isCancelled else { return }
            suggested = []
            print("WARNING: loading Ask suggestions failed: \(error)")
        }
    }

    func ask(_ q: String) {
        askTask?.cancel()
        let startedAt = Date()
        phase = .thinking
        question = q
        answer = nil
        inputText = ""
        askedAt = startedAt
        answeredIn = nil
        errorMessage = nil

        askTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await self.container.askService.ask(q)
                let elapsed = max(0, Date().timeIntervalSince(startedAt))
                guard !Task.isCancelled else { return }

                if elapsed < 0.6 {
                    try? await Task.sleep(for: .seconds(0.6 - elapsed))
                    guard !Task.isCancelled else { return }
                }

                self.answer = result
                self.answeredIn = max(0, Date().timeIntervalSince(startedAt))
                self.phase = .answered
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.phase = .answered
            }
        }
    }

    func reset() {
        askTask?.cancel()
        askTask = nil
        phase = .idle
        question = ""
        answer = nil
        inputText = ""
        askedAt = nil
        answeredIn = nil
        errorMessage = nil
    }
}
