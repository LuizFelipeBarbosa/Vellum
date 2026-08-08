import Foundation

/// Ranks notes that may be related to a source text.
public protocol RelatedNoteRanking: Sendable {
    /// Ranks candidates by relevance to `text`; returns at most `limit`, most relevant first.
    func rankRelatedNotes(for text: String, candidates: [NoteRef], limit: Int) async -> [NoteRef]
}

/// Ranks related notes by lexical overlap between the source text and note metadata.
public struct LexicalRelatedNoteRanker: RelatedNoteRanking {
    /// Creates a lexical related-note ranker.
    public init() {}

    /// Ranks candidates using Jaccard similarity over their title and preview terms.
    public func rankRelatedNotes(
        for text: String,
        candidates: [NoteRef],
        limit: Int
    ) async -> [NoteRef] {
        guard limit > 0 else { return [] }

        let textTerms = TermScoring.queryTerms(from: text)
        guard !textTerms.isEmpty else { return [] }

        let scoredCandidates = candidates.compactMap { candidate -> (note: NoteRef, score: Double)? in
            let candidateTerms = TermScoring.queryTerms(
                from: candidate.title + " " + candidate.preview
            )
            let overlapCount = textTerms.intersection(candidateTerms).count
            guard overlapCount > 0 else { return nil }

            let unionCount = textTerms.count + candidateTerms.count - overlapCount
            return (candidate, Double(overlapCount) / Double(unionCount))
        }
        let ranked = scoredCandidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let lhsTitle = lhs.note.title.lowercased()
            let rhsTitle = rhs.note.title.lowercased()
            if lhsTitle != rhsTitle {
                return lhsTitle < rhsTitle
            }
            return lhs.note.id.uuidString < rhs.note.id.uuidString
        }
        return ranked.prefix(limit).map(\.note)
    }
}
