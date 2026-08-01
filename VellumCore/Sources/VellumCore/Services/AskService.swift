import Foundation

public actor AskService {
    private let notes: any NoteRepository
    private let answerer: any AskAnswering
    private let activity: (any ActivityRepository)?

    public init(
        notes: any NoteRepository,
        answerer: any AskAnswering,
        activity: (any ActivityRepository)?
    ) {
        self.notes = notes
        self.answerer = answerer
        self.activity = activity
    }

    public func ask(_ question: String) async throws -> AskAnswer {
        let sources = try await notes.listNotes().map { note in
            AskSource(
                noteID: note.id,
                title: note.title,
                noteType: note.noteType,
                pages: note.pages
                    .sorted(by: Self.sortPages)
                    .filter {
                        !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    .map { AskPage(pageID: $0.id, plainText: $0.plainText) }
            )
        }
        let answer = try await answerer.answer(
            question: question,
            context: AskContext(sources: sources)
        )
        if let activity {
            try await activity.append(
                ActivityEvent(
                    id: UUID(),
                    noteID: nil,
                    createdAt: Date(),
                    kind: .questionAnswered,
                    message: "Answered a question."
                )
            )
        }
        return answer
    }

    public func suggestedQuestions() async throws -> [String] {
        let qualifyingNotes = try await notes.listNotes()
            .filter { note in
                note.pages.contains {
                    !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
            .sorted { StableOrder.descending($0, $1, by: \.updatedAt) }
        return qualifyingNotes.prefix(3).map {
            "What do my notes say about \($0.title)?"
        }
    }

    private static func sortPages(_ lhs: NotePage, _ rhs: NotePage) -> Bool {
        StableOrder.ascending(lhs, rhs, by: \.order)
    }
}
