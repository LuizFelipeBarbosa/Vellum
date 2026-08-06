import Foundation

public struct HeuristicAskAnswerer: AskAnswering, Sendable {
    public init() {}

    public func answer(question: String, context: AskContext) async throws -> AskAnswer {
        let queryTerms = TermScoring.queryTerms(from: question)
        guard !queryTerms.isEmpty else {
            return Self.noMatchAnswer(question: question)
        }

        var hits: [AskHit] = []
        for source in context.sources {
            for page in source.pages {
                let pageText = page.plainText.lowercased()
                let score = TermScoring.occurrenceCount(in: pageText, terms: queryTerms)
                if score > 0 {
                    hits.append(AskHit(source: source, page: page, score: score))
                }
            }
        }
        hits.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            if $0.source.noteID != $1.source.noteID {
                return $0.source.noteID.uuidString < $1.source.noteID.uuidString
            }
            return $0.page.pageID.uuidString < $1.page.pageID.uuidString
        }
        hits = Array(hits.prefix(3))

        guard !hits.isEmpty else {
            return Self.noMatchAnswer(question: question)
        }

        var segments: [AskSegment] = [
            .text("Here's what I found in your notes: ", emphasized: false)
        ]
        var citations: [Citation] = []
        for (offset, hit) in hits.enumerated() {
            let index = offset + 1
            let excerpt = TermScoring.excerpt(from: hit.page.plainText, terms: queryTerms)
            segments.append(.text(excerpt, emphasized: false))
            segments.append(.citation(index: index))
            citations.append(
                Citation(
                    id: UUID(),
                    index: index,
                    noteID: hit.source.noteID,
                    pageID: hit.page.pageID,
                    noteTitle: hit.source.title,
                    noteType: hit.source.noteType,
                    excerpt: excerpt
                )
            )
        }

        let topSourceID = hits[0].source.noteID
        var seenTitles: Set<String> = []
        let followUps = hits.compactMap { hit -> String? in
            guard hit.source.noteID != topSourceID,
                  seenTitles.insert(hit.source.title).inserted else {
                return nil
            }
            return "What do my notes say about \(hit.source.title)?"
        }
        .prefix(2)

        return AskAnswer(
            question: question,
            segments: segments,
            citations: citations,
            followUps: Array(followUps),
            answeredAt: Date()
        )
    }

    private static func noMatchAnswer(question: String) -> AskAnswer {
        AskAnswer(
            question: question,
            segments: [
                .text("I couldn't find anything about that in your notes.", emphasized: false)
            ],
            citations: [],
            followUps: [],
            answeredAt: Date()
        )
    }

}

private struct AskHit {
    let source: AskSource
    let page: AskPage
    let score: Int
}
