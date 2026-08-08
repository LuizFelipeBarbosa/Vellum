import Foundation
import Testing
@testable import VellumCore

@Test("Lexical related-note ranking orders by Jaccard relevance and excludes zero overlap")
func lexicalRelatedNoteRankingOrdersByRelevance() async {
    let exact = NoteRef(id: UUID(), title: "Concurrency", preview: "Swift actor design")
    let partial = NoteRef(id: UUID(), title: "Swift patterns", preview: "Actor examples")
    let low = NoteRef(id: UUID(), title: "Design archive", preview: "Reference photos")
    let unrelated = NoteRef(id: UUID(), title: "Garden plans", preview: "Tomatoes and basil")
    let candidates = [unrelated, low, exact, partial]

    let ranked = await LexicalRelatedNoteRanker().rankRelatedNotes(
        for: "Swift concurrency actor design",
        candidates: candidates,
        limit: 10
    )

    #expect(ranked.map(\.id) == [exact.id, partial.id, low.id])
}

@Test("Lexical related-note ranking guards empty terms and nonpositive limits")
func lexicalRelatedNoteRankingGuardsDegenerateInputs() async {
    let candidate = NoteRef(id: UUID(), title: "Swift concurrency", preview: "Actors")
    let ranker = LexicalRelatedNoteRanker()

    #expect(await ranker.rankRelatedNotes(for: "", candidates: [candidate], limit: 1).isEmpty)
    #expect(await ranker.rankRelatedNotes(for: "the and of", candidates: [candidate], limit: 1).isEmpty)
    #expect(await ranker.rankRelatedNotes(for: "swift", candidates: [candidate], limit: 0).isEmpty)
    #expect(await ranker.rankRelatedNotes(for: "swift", candidates: [candidate], limit: -1).isEmpty)
}

@Test("Lexical related-note ranking respects its limit")
func lexicalRelatedNoteRankingRespectsLimit() async {
    let candidates = [
        NoteRef(id: UUID(), title: "Swift actors", preview: "Concurrency design"),
        NoteRef(id: UUID(), title: "Swift patterns", preview: "Concurrency"),
        NoteRef(id: UUID(), title: "Swift notes", preview: "Reference"),
    ]

    let ranked = await LexicalRelatedNoteRanker().rankRelatedNotes(
        for: "Swift concurrency actor design",
        candidates: candidates,
        limit: 2
    )

    #expect(ranked.count == 2)
    #expect(ranked.map(\.id) == Array(candidates.prefix(2)).map(\.id))
}

@Test("Lexical related-note ranking uses deterministic title and ID tie breaks")
func lexicalRelatedNoteRankingIsDeterministic() async throws {
    let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let betaID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
    let candidates = [
        NoteRef(id: betaID, title: "Beta", preview: "Swift"),
        NoteRef(id: secondID, title: "alpha", preview: "Swift"),
        NoteRef(id: firstID, title: "Alpha", preview: "Swift"),
    ]
    let expectedIDs = [firstID, secondID, betaID]
    let ranker = LexicalRelatedNoteRanker()

    for _ in 0..<25 {
        let ranked = await ranker.rankRelatedNotes(
            for: "Swift",
            candidates: candidates,
            limit: candidates.count
        )
        #expect(ranked.map(\.id) == expectedIDs)
    }
}
