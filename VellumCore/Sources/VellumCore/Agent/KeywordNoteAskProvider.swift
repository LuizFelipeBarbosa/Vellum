import Foundation

/// A deterministic keyword-based provider. No-match streams omit a citations event,
/// and summaries of empty notes return `"This note is empty."`.
public struct KeywordNoteAskProvider: NoteAskProviding {
    private let asFallback: Bool
    private let fallbackReason: String

    public init(
        asFallback: Bool = false,
        fallbackReason: String = "Apple Intelligence is unavailable"
    ) {
        self.asFallback = asFallback
        self.fallbackReason = fallbackReason
    }

    public func availability() async -> NoteAskAvailability {
        asFallback ? .fallback(reason: fallbackReason) : .available
    }

    public func makeSession(source: AskSource) async -> any NoteAskSession {
        KeywordNoteAskSession(source: source)
    }
}

private actor KeywordNoteAskSession: NoteAskSession {
    nonisolated let source: AskSource

    init(source: AskSource) {
        self.source = source
    }

    nonisolated func ask(
        _ question: String
    ) -> AsyncThrowingStream<NoteAskStreamEvent, Error> {
        let source = source
        return AsyncThrowingStream { continuation in
            let terms = TermScoring.queryTerms(from: question)
            let hits = Self.rankedHits(in: source, terms: terms)

            guard !terms.isEmpty, !hits.isEmpty else {
                continuation.yield(
                    .partial("I couldn't find anything about that in this note.")
                )
                continuation.yield(.done)
                continuation.finish()
                return
            }

            let citations = hits.enumerated().map { offset, hit in
                Citation(
                    id: UUID(),
                    index: offset + 1,
                    noteID: source.noteID,
                    pageID: hit.page.pageID,
                    noteTitle: source.title,
                    noteType: source.noteType,
                    excerpt: TermScoring.excerpt(from: hit.page.plainText, terms: terms)
                )
            }
            continuation.yield(.citations(citations))

            var cumulativeAnswer = "Here's what I found in this note."
            continuation.yield(.partial(cumulativeAnswer))
            for hit in hits.prefix(2) {
                let excerpt = TermScoring.excerpt(from: hit.page.plainText, terms: terms)
                cumulativeAnswer += " \(excerpt)."
                continuation.yield(.partial(cumulativeAnswer))
            }

            continuation.yield(.done)
            continuation.finish()
        }
    }

    func summarize() async throws -> String {
        let fullText = source.pages.map(\.plainText).joined(separator: "\n")
        let sentences = TermScoring.sentenceComponents(from: fullText)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
        guard !sentences.isEmpty else { return "This note is empty." }
        return sentences.joined(separator: ". ") + "."
    }

    private nonisolated static func rankedHits(
        in source: AskSource,
        terms: Set<String>
    ) -> [PageHit] {
        guard !terms.isEmpty else { return [] }

        var hits = source.pages.compactMap { page -> PageHit? in
            let score = NoteAskContextPacker.paragraphs(from: page.plainText).reduce(into: 0) {
                $0 += TermScoring.occurrenceCount(in: $1.lowercased(), terms: terms)
            }
            return score > 0 ? PageHit(page: page, score: score) : nil
        }
        hits.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.page.pageID.uuidString < $1.page.pageID.uuidString
        }
        return Array(hits.prefix(3))
    }
}

private struct PageHit: Sendable {
    let page: AskPage
    let score: Int
}
