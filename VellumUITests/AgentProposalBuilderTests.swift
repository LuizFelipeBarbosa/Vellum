import XCTest
@testable import Vellum
import VellumCore
import Foundation

@MainActor
final class AgentProposalBuilderTests: XCTestCase {
    func testTagAlreadyPresentIsDroppedCaseInsensitively() {
        let context = makeContext(existingTags: ["Work"])
        let proposals = build(
            extraction: AgentExtraction(tags: ["work", "Ideas"]),
            context: context
        )

        XCTAssertEqual(tagValues(in: proposals), ["Ideas"])
    }

    func testDuplicateTagsAreDeduplicatedKeepingFirstOccurrence() {
        let proposals = build(
            extraction: AgentExtraction(tags: ["Travel", "travel", "TRAVEL"]),
            context: makeContext()
        )

        XCTAssertEqual(tagValues(in: proposals), ["Travel"])
    }

    func testWhitespaceTagIsDropped() {
        let proposals = build(
            extraction: AgentExtraction(tags: ["", "  \n ", "valid"]),
            context: makeContext()
        )

        XCTAssertEqual(tagValues(in: proposals), ["valid"])
    }

    func testTagsAreCappedAtFourSurvivingValues() {
        let proposals = build(
            extraction: AgentExtraction(tags: ["one", "two", "three", "four", "five"]),
            context: makeContext()
        )

        XCTAssertEqual(tagValues(in: proposals), ["one", "two", "three", "four"])
    }

    func testExistingEntityNameIsDroppedCaseInsensitively() {
        let context = makeContext(existingEntityNames: ["Ada Lovelace"])
        let extraction = AgentExtraction(
            entities: [
                makeEntity(name: "ada lovelace"),
                makeEntity(name: "Analytical Engine", kind: "document"),
            ]
        )

        XCTAssertEqual(
            entityNames(in: build(extraction: extraction, context: context)),
            ["Analytical Engine"]
        )
    }

    func testWhitespaceEntityNameIsDropped() {
        let extraction = AgentExtraction(
            entities: [makeEntity(name: " \n "), makeEntity(name: "Planning")]
        )

        XCTAssertEqual(
            entityNames(in: build(extraction: extraction, context: makeContext())),
            ["Planning"]
        )
    }

    func testEntitiesAreCappedAtFiveSurvivingValues() {
        let extraction = AgentExtraction(
            entities: (1...6).map { makeEntity(name: "Entity \($0)") }
        )

        XCTAssertEqual(
            entityNames(in: build(extraction: extraction, context: makeContext())),
            ["Entity 1", "Entity 2", "Entity 3", "Entity 4", "Entity 5"]
        )
    }

    func testUnknownEntityKindDefaultsToTopic() throws {
        let proposals = build(
            extraction: AgentExtraction(entities: [makeEntity(name: "Roadmap", kind: "unknown")]),
            context: makeContext()
        )
        let operation = try XCTUnwrap(proposals.first?.operation)

        guard case .extractEntity(_, let kind, _, _) = operation else {
            return XCTFail("Expected an entity proposal")
        }
        XCTAssertEqual(kind.rawValue, EntityKind.topic.rawValue)
    }

    func testActionItemsDropWhitespaceAndCapAtFourSurvivingValues() {
        let extraction = AgentExtraction(
            actionItems: ["", " \n ", "one", "two", "three", "four", "five"]
        )

        XCTAssertEqual(
            taskValues(in: build(extraction: extraction, context: makeContext())),
            ["one", "two", "three", "four"]
        )
    }

    func testSummaryIsEmittedOnlyWhenCanonicalTextExceedsThreeHundredCharacters() {
        let extraction = AgentExtraction(summary: "A useful summary.")
        let shortProposals = build(
            extraction: extraction,
            context: makeContext(canonicalText: String(repeating: "a", count: 300))
        )
        let longProposals = build(
            extraction: extraction,
            context: makeContext(canonicalText: String(repeating: "a", count: 301))
        )

        XCTAssertTrue(summaryValues(in: shortProposals).isEmpty)
        XCTAssertEqual(summaryValues(in: longProposals), ["A useful summary."])
    }

    func testWhitespaceSummaryIsDroppedForLongNote() {
        let proposals = build(
            extraction: AgentExtraction(summary: " \n "),
            context: makeContext(canonicalText: String(repeating: "a", count: 301))
        )

        XCTAssertTrue(summaryValues(in: proposals).isEmpty)
    }

    func testFileToSpaceIsSkippedWhenNoteAlreadyHasSpace() {
        let context = makeContext(currentSpaceID: UUID())
        let proposals = build(
            organize: AgentOrganizeSuggestion(spaceName: "Projects", relatedNoteOrdinals: []),
            context: context
        )

        XCTAssertFalse(proposals.contains { proposal in
            if case .fileToSpace = proposal.operation { return true }
            return false
        })
    }

    func testFileToSpaceUsesMatchingExistingSpaceColorCaseInsensitively() throws {
        let space = Space(
            id: UUID(),
            name: "Projects",
            color: .green,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let proposals = build(
            organize: AgentOrganizeSuggestion(
                spaceName: " projects ",
                relatedNoteOrdinals: []
            ),
            context: makeContext(spaces: [space])
        )
        let operation = try XCTUnwrap(proposals.first?.operation)

        guard case .fileToSpace(let name, let color) = operation else {
            return XCTFail("Expected a file-to-space proposal")
        }
        XCTAssertEqual(name, "Projects")
        XCTAssertEqual(color.rawValue, SpaceColor.green.rawValue)
    }

    func testFileToSpaceAllowsNewSpaceWithBlueDefault() throws {
        let proposals = build(
            organize: AgentOrganizeSuggestion(spaceName: "Research", relatedNoteOrdinals: []),
            context: makeContext()
        )
        let operation = try XCTUnwrap(proposals.first?.operation)

        guard case .fileToSpace(let name, let color) = operation else {
            return XCTFail("Expected a file-to-space proposal")
        }
        XCTAssertEqual(name, "Research")
        XCTAssertEqual(color.rawValue, SpaceColor.blue.rawValue)
    }

    func testFileToSpaceStripsEchoedListMarkerAndMatchesExistingSpace() throws {
        let space = Space(
            id: UUID(),
            name: "Work",
            color: .green,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let proposals = build(
            organize: AgentOrganizeSuggestion(
                spaceName: "1. Work",
                relatedNoteOrdinals: []
            ),
            context: makeContext(spaces: [space])
        )
        let operation = try XCTUnwrap(proposals.first?.operation)

        guard case .fileToSpace(let name, let color) = operation else {
            return XCTFail("Expected a file-to-space proposal")
        }
        XCTAssertEqual(name, "Work")
        XCTAssertEqual(color.rawValue, SpaceColor.green.rawValue)
    }

    func testWhitespaceSpaceNameIsDropped() {
        let proposals = build(
            organize: AgentOrganizeSuggestion(spaceName: " \n ", relatedNoteOrdinals: []),
            context: makeContext()
        )

        XCTAssertTrue(proposals.isEmpty)
    }

    func testOutOfRangeLinkOrdinalsAreDropped() {
        let candidates = [makeNoteRef(title: "First"), makeNoteRef(title: "Second")]
        let proposals = build(
            organize: AgentOrganizeSuggestion(
                spaceName: nil,
                relatedNoteOrdinals: [-1, 0, 3, 2]
            ),
            candidates: candidates,
            context: makeContext()
        )

        XCTAssertEqual(linkedNoteIDs(in: proposals), [candidates[1].id])
    }

    func testExistingLinkTargetIsDropped() {
        let candidate = makeNoteRef(title: "Existing")
        let context = makeContext(existingLinkTargetIDs: [candidate.id])
        let proposals = build(
            organize: AgentOrganizeSuggestion(spaceName: nil, relatedNoteOrdinals: [1]),
            candidates: [candidate],
            context: context
        )

        XCTAssertTrue(linkedNoteIDs(in: proposals).isEmpty)
    }

    func testSelfLinkTargetIsDropped() {
        let noteID = UUID()
        let candidate = NoteRef(id: noteID, title: "Current note")
        let proposals = build(
            organize: AgentOrganizeSuggestion(spaceName: nil, relatedNoteOrdinals: [1]),
            candidates: [candidate],
            context: makeContext(noteID: noteID)
        )

        XCTAssertTrue(linkedNoteIDs(in: proposals).isEmpty)
    }

    func testDuplicateResolvedLinkTargetsAreDeduplicatedKeepingFirst() {
        let candidates = [makeNoteRef(title: "First"), makeNoteRef(title: "Second")]
        let proposals = build(
            organize: AgentOrganizeSuggestion(
                spaceName: nil,
                relatedNoteOrdinals: [1, 1, 2]
            ),
            candidates: candidates,
            context: makeContext()
        )

        XCTAssertEqual(linkedNoteIDs(in: proposals), candidates.map(\.id))
    }

    func testLinksAreCappedAtThreeSurvivingValues() {
        let candidates = (1...4).map { makeNoteRef(title: "Candidate \($0)") }
        let proposals = build(
            organize: AgentOrganizeSuggestion(
                spaceName: nil,
                relatedNoteOrdinals: [1, 2, 3, 4]
            ),
            candidates: candidates,
            context: makeContext()
        )

        XCTAssertEqual(linkedNoteIDs(in: proposals), Array(candidates.prefix(3)).map(\.id))
    }

    func testConfidenceConstantsMatchEachOperationType() {
        let candidate = makeNoteRef(title: "Related")
        let proposals = build(
            extraction: AgentExtraction(
                tags: ["work"],
                entities: [makeEntity(name: "Ada Lovelace", kind: "person")],
                actionItems: ["Send the plan"],
                summary: "A concise summary."
            ),
            organize: AgentOrganizeSuggestion(
                spaceName: "Projects",
                relatedNoteOrdinals: [1]
            ),
            candidates: [candidate],
            context: makeContext(canonicalText: String(repeating: "a", count: 301))
        )

        var coveredOperations: Set<String> = []
        for proposal in proposals {
            switch proposal.operation {
            case .addTag:
                XCTAssertEqual(proposal.confidence, 0.7, accuracy: 0.000_001)
                coveredOperations.insert("tag")
            case .extractEntity:
                XCTAssertEqual(proposal.confidence, 0.65, accuracy: 0.000_001)
                coveredOperations.insert("entity")
            case .extractTask:
                XCTAssertEqual(proposal.confidence, 0.6, accuracy: 0.000_001)
                coveredOperations.insert("task")
            case .createSummary:
                XCTAssertEqual(proposal.confidence, 0.6, accuracy: 0.000_001)
                coveredOperations.insert("summary")
            case .fileToSpace:
                XCTAssertEqual(proposal.confidence, 0.55, accuracy: 0.000_001)
                coveredOperations.insert("space")
            case .linkNotes:
                XCTAssertEqual(proposal.confidence, 0.6, accuracy: 0.000_001)
                coveredOperations.insert("link")
            case .suggestTitle:
                XCTFail("The builder must never suggest titles")
            }
        }
        XCTAssertEqual(
            coveredOperations,
            Set(["tag", "entity", "task", "summary", "space", "link"])
        )
    }

    func testEveryProposalUsesContextRevision() {
        let context = makeContext(noteRevision: 42)
        let proposals = build(
            extraction: AgentExtraction(
                tags: ["work"],
                entities: [makeEntity(name: "Roadmap")],
                actionItems: ["Review roadmap"]
            ),
            context: context
        )

        XCTAssertFalse(proposals.isEmpty)
        XCTAssertTrue(proposals.allSatisfy { $0.basedOnRevision == 42 })
    }

    func testEveryProposalUsesContextMetadataAndPendingStatus() {
        let noteID = UUID()
        let context = makeContext(noteID: noteID, noteRevision: 7)
        let earliestCreationDate = Date()
        let proposals = build(
            extraction: AgentExtraction(
                tags: ["work"],
                entities: [makeEntity(name: "Roadmap")],
                actionItems: ["Review roadmap"]
            ),
            context: context
        )
        let latestCreationDate = Date()

        XCTAssertEqual(Set(proposals.map(\.id)).count, proposals.count)
        for proposal in proposals {
            XCTAssertEqual(proposal.noteID, noteID)
            XCTAssertEqual(proposal.basedOnRevision, 7)
            XCTAssertEqual(proposal.status.rawValue, ProposalStatus.pending.rawValue)
            XCTAssertGreaterThanOrEqual(proposal.createdAt, earliestCreationDate)
            XCTAssertLessThanOrEqual(proposal.createdAt, latestCreationDate)
            XCTAssertFalse(proposal.title.isEmpty)
            XCTAssertFalse(proposal.explanation.isEmpty)
        }
    }

    func testOrdinalMapsToCorrectOneBasedCandidateAndUsesRelatedKind() throws {
        let candidates = [
            makeNoteRef(title: "First"),
            makeNoteRef(title: "Second"),
            makeNoteRef(title: "Third"),
        ]
        let proposals = build(
            organize: AgentOrganizeSuggestion(spaceName: nil, relatedNoteOrdinals: [2]),
            candidates: candidates,
            context: makeContext()
        )
        let operation = try XCTUnwrap(proposals.first?.operation)

        guard case .linkNotes(let targetNoteID, let kind) = operation else {
            return XCTFail("Expected a link proposal")
        }
        XCTAssertEqual(targetNoteID, candidates[1].id)
        XCTAssertEqual(kind.rawValue, LinkKind.related.rawValue)
    }

    func testExtractedEntitiesAndTasksHaveNoPageGrounding() {
        let proposals = build(
            extraction: AgentExtraction(
                entities: [makeEntity(name: "Roadmap")],
                actionItems: ["Review roadmap"]
            ),
            context: makeContext()
        )

        for proposal in proposals {
            switch proposal.operation {
            case .extractEntity(_, _, let pageID, _):
                XCTAssertNil(pageID)
            case .extractTask(_, let pageID):
                XCTAssertNil(pageID)
            default:
                break
            }
        }
    }

    func testSuggestTitleIsNeverEmittedForRepresentativeFullInput() {
        let candidate = makeNoteRef(title: "Related")
        let proposals = build(
            extraction: AgentExtraction(
                tags: ["work"],
                entities: [makeEntity(name: "Ada Lovelace", kind: "person")],
                actionItems: ["Send the plan"],
                summary: "A concise summary."
            ),
            organize: AgentOrganizeSuggestion(
                spaceName: "Projects",
                relatedNoteOrdinals: [1]
            ),
            candidates: [candidate],
            context: makeContext(canonicalText: String(repeating: "a", count: 301))
        )

        XCTAssertFalse(proposals.contains { proposal in
            if case .suggestTitle = proposal.operation { return true }
            return false
        })
    }

    private func build(
        extraction: AgentExtraction = .empty,
        organize: AgentOrganizeSuggestion? = nil,
        candidates: [NoteRef] = [],
        context: AgentContext
    ) -> [AgentProposal] {
        AgentProposalBuilder.proposals(
            extraction: extraction,
            organize: organize,
            rankedCandidates: candidates,
            context: context
        )
    }

    private func makeContext(
        noteID: UUID = UUID(),
        noteRevision: Int = 1,
        canonicalText: String = "A short note.",
        currentSpaceID: UUID? = nil,
        spaces: [Space] = [],
        existingTags: [String] = [],
        existingLinkTargetIDs: [UUID] = [],
        existingEntityNames: [String] = []
    ) -> AgentContext {
        AgentContext(
            noteID: noteID,
            noteRevision: noteRevision,
            title: "Test note",
            canonicalText: canonicalText,
            currentSpaceID: currentSpaceID,
            spaces: spaces,
            otherNotes: [],
            existingTags: existingTags,
            existingLinkTargetIDs: existingLinkTargetIDs,
            existingEntityNames: existingEntityNames
        )
    }

    private func makeEntity(
        name: String,
        kind: String = "topic",
        excerpt: String = "Grounding excerpt"
    ) -> AgentExtractedEntity {
        AgentExtractedEntity(name: name, kind: kind, excerpt: excerpt)
    }

    private func makeNoteRef(title: String) -> NoteRef {
        NoteRef(id: UUID(), title: title, preview: "Preview for \(title)")
    }

    private func tagValues(in proposals: [AgentProposal]) -> [String] {
        proposals.compactMap { proposal in
            guard case .addTag(let tag) = proposal.operation else { return nil }
            return tag
        }
    }

    private func entityNames(in proposals: [AgentProposal]) -> [String] {
        proposals.compactMap { proposal in
            guard case .extractEntity(let name, _, _, _) = proposal.operation else {
                return nil
            }
            return name
        }
    }

    private func taskValues(in proposals: [AgentProposal]) -> [String] {
        proposals.compactMap { proposal in
            guard case .extractTask(let text, _) = proposal.operation else { return nil }
            return text
        }
    }

    private func summaryValues(in proposals: [AgentProposal]) -> [String] {
        proposals.compactMap { proposal in
            guard case .createSummary(let summary) = proposal.operation else { return nil }
            return summary
        }
    }

    private func linkedNoteIDs(in proposals: [AgentProposal]) -> [UUID] {
        proposals.compactMap { proposal in
            guard case .linkNotes(let targetNoteID, _) = proposal.operation else { return nil }
            return targetNoteID
        }
    }
}

@MainActor
final class EmbeddingRelatedNoteRankerTests: XCTestCase {
    func testCosineSimilarityOfIdenticalVectorsIsOne() {
        XCTAssertEqual(
            EmbeddingRelatedNoteRanker.cosineSimilarity([1, 2, 3], [1, 2, 3]),
            1,
            accuracy: 0.000_001
        )
    }

    func testCosineSimilarityOfOrthogonalVectorsIsZero() {
        XCTAssertEqual(
            EmbeddingRelatedNoteRanker.cosineSimilarity([1, 0], [0, 1]),
            0,
            accuracy: 0.000_001
        )
    }

    func testRankingTieBreakUsesSimilarityThenLowercasedTitleThenID() throws {
        let lowerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let alpha = NoteRef(id: higherID, title: "alpha")
        let beta = NoteRef(id: lowerID, title: "Beta")
        let alphaWithLowerID = NoteRef(id: lowerID, title: "ALPHA")

        XCTAssertTrue(
            EmbeddingRelatedNoteRanker.ranksBefore(
                lhsSimilarity: 0.8,
                lhsNote: beta,
                rhsSimilarity: 0.7,
                rhsNote: alpha
            )
        )
        XCTAssertTrue(
            EmbeddingRelatedNoteRanker.ranksBefore(
                lhsSimilarity: 0.7,
                lhsNote: alpha,
                rhsSimilarity: 0.7,
                rhsNote: beta
            )
        )
        XCTAssertTrue(
            EmbeddingRelatedNoteRanker.ranksBefore(
                lhsSimilarity: 0.7,
                lhsNote: alphaWithLowerID,
                rhsSimilarity: 0.7,
                rhsNote: alpha
            )
        )
    }
}
