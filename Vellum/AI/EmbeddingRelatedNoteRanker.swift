import Foundation
import NaturalLanguage
import VellumCore

struct EmbeddingRelatedNoteRanker: RelatedNoteRanking {
    private static let sourceCharacterLimit = 1_000

    init() {}

    /// Ranks related notes using an English sentence embedding.
    ///
    /// Only the first 1,000 characters of the source are embedded because sentence
    /// embeddings become less representative when they are given long documents.
    func rankRelatedNotes(
        for text: String,
        candidates: [NoteRef],
        limit: Int
    ) async -> [NoteRef] {
        guard limit > 0 else { return [] }

        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return await LexicalRelatedNoteRanker().rankRelatedNotes(
                for: text,
                candidates: candidates,
                limit: limit
            )
        }

        let cappedText = String(text.prefix(Self.sourceCharacterLimit))
        guard let sourceVector = Self.vector(for: cappedText, embedding: embedding) else {
            return await LexicalRelatedNoteRanker().rankRelatedNotes(
                for: text,
                candidates: candidates,
                limit: limit
            )
        }

        let scoredCandidates = candidates.compactMap { candidate -> ScoredCandidate? in
            let candidateText = candidate.title + " " + candidate.preview
            guard let candidateVector = Self.vector(for: candidateText, embedding: embedding) else {
                return nil
            }
            return ScoredCandidate(
                note: candidate,
                similarity: Self.cosineSimilarity(sourceVector, candidateVector)
            )
        }

        return scoredCandidates
            .sorted {
                Self.ranksBefore(
                    lhsSimilarity: $0.similarity,
                    lhsNote: $0.note,
                    rhsSimilarity: $1.similarity,
                    rhsNote: $1.note
                )
            }
            .prefix(limit)
            .map(\.note)
    }

    static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return 0 }

        var dotProduct = 0.0
        var lhsMagnitudeSquared = 0.0
        var rhsMagnitudeSquared = 0.0
        for (lhsValue, rhsValue) in zip(lhs, rhs) {
            dotProduct += lhsValue * rhsValue
            lhsMagnitudeSquared += lhsValue * lhsValue
            rhsMagnitudeSquared += rhsValue * rhsValue
        }

        guard lhsMagnitudeSquared > 0, rhsMagnitudeSquared > 0 else { return 0 }
        return dotProduct / sqrt(lhsMagnitudeSquared * rhsMagnitudeSquared)
    }

    static func ranksBefore(
        lhsSimilarity: Double,
        lhsNote: NoteRef,
        rhsSimilarity: Double,
        rhsNote: NoteRef
    ) -> Bool {
        if lhsSimilarity != rhsSimilarity {
            return lhsSimilarity > rhsSimilarity
        }

        let lhsTitle = lhsNote.title.lowercased()
        let rhsTitle = rhsNote.title.lowercased()
        if lhsTitle != rhsTitle {
            return lhsTitle < rhsTitle
        }
        return lhsNote.id.uuidString < rhsNote.id.uuidString
    }

    private static func vector(for text: String, embedding: NLEmbedding) -> [Double]? {
        embedding.vector(for: text)
    }

    private struct ScoredCandidate {
        let note: NoteRef
        let similarity: Double
    }
}
