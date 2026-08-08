import Foundation
import FoundationModels
import VellumCore

@available(iOS 26.0, *)
struct FoundationModelsVellumAgent: VellumAgent {
    private static let extractionCharacterBudget = 9_000
    private static let organizationCharacterBudget = 4_000
    private static let candidatePreviewCharacterLimit = 120
    private static let extractionResponseTokenBudget = 700
    private static let organizationResponseTokenBudget = 300

    let fallback: any VellumAgent
    let ranker: any RelatedNoteRanking

    init(fallback: any VellumAgent, ranker: any RelatedNoteRanking) {
        self.fallback = fallback
        self.ranker = ranker
    }

    func analyze(
        event: WorkspaceEvent,
        context: AgentContext
    ) async throws -> [AgentProposal] {
        let canonicalText = context.canonicalText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !canonicalText.isEmpty else { return [] }

        guard AppleIntelligence.availability() == .available else {
            return try await fallback.analyze(event: event, context: context)
        }

        let extraction: AgentExtraction
        do {
            let session = LanguageModelSession(instructions: Self.extractionInstructions)
            let response = try await session.respond(
                to: Self.extractionPrompt(context: context),
                generating: NoteExtraction.self,
                options: GenerationOptions(
                    maximumResponseTokens: Self.extractionResponseTokenBudget
                )
            )
            extraction = Self.plainExtraction(from: response.content)
        } catch {
            return try await fallback.analyze(event: event, context: context)
        }

        var proposals = AgentProposalBuilder.proposals(
            extraction: extraction,
            organize: nil,
            rankedCandidates: [],
            context: context
        )

        guard !context.spaces.isEmpty || !context.otherNotes.isEmpty else {
            return proposals
        }

        let rankedCandidates = await ranker.rankRelatedNotes(
            for: canonicalText,
            candidates: context.otherNotes,
            limit: 10
        )
        // Call 2 sees this exact order as 1-based ordinals, and the builder resolves
        // those ordinals against the same unchanged array.

        do {
            let session = LanguageModelSession(instructions: Self.organizationInstructions)
            let response = try await session.respond(
                to: Self.organizationPrompt(
                    context: context,
                    rankedCandidates: rankedCandidates
                ),
                generating: OrganizeSuggestion.self,
                options: GenerationOptions(
                    maximumResponseTokens: Self.organizationResponseTokenBudget
                )
            )
            let organize = AgentOrganizeSuggestion(
                spaceName: response.content.spaceName,
                relatedNoteOrdinals: response.content.relatedNoteOrdinals
            )
            proposals.append(
                contentsOf: AgentProposalBuilder.proposals(
                    extraction: .empty,
                    organize: organize,
                    rankedCandidates: rankedCandidates,
                    context: context
                )
            )
        } catch {
            return proposals
        }

        return proposals
    }

    private static let extractionInstructions = """
    You extract structure from a personal handwritten note.
    Extract only content grounded in the provided note text.
    Never invent facts, names, tasks, or details that are not present in the note.
    """

    private static let organizationInstructions = """
    You organize a personal handwritten note for filing and related-note discovery.
    Base every suggestion only on the provided note, space names, and note candidates.
    You may suggest a short new space name when no existing space fits.
    Select related notes only by their 1-based candidate ordinals, and never invent candidates or facts.
    """

    private static func extractionPrompt(context: AgentContext) -> String {
        let noteText = TokenBudget.truncateHeadAndTail(
            context.canonicalText,
            charBudget: extractionCharacterBudget
        )
        return """
        Note title:
        \(context.title)

        Note text:
        \(noteText)

        Extract tags, grounded entities, concrete action items, and a concise summary.
        """
    }

    private static func organizationPrompt(
        context: AgentContext,
        rankedCandidates: [NoteRef]
    ) -> String {
        let noteText = TokenBudget.truncateHeadAndTail(
            context.canonicalText,
            charBudget: organizationCharacterBudget
        )
        let spaces = context.spaces.isEmpty
            ? "(none)"
            : context.spaces.enumerated().map { offset, space in
                "\(offset + 1). \(space.name)"
            }.joined(separator: "\n")
        let candidates = rankedCandidates.isEmpty
            ? "(none)"
            : rankedCandidates.enumerated().map { offset, candidate in
                let preview = String(candidate.preview.prefix(candidatePreviewCharacterLimit))
                return "\(offset + 1). \(candidate.title) — \(preview)"
            }.joined(separator: "\n")

        return """
        Note title:
        \(context.title)

        Note text:
        \(noteText)

        Existing spaces (choose an existing name when it fits; otherwise suggest a short new name):
        \(spaces)

        Related-note candidates (use only these 1-based ordinals):
        \(candidates)

        Suggest one space only if appropriate and up to 3 related-note ordinals, most relevant first.
        """
    }

    private static func plainExtraction(from extraction: NoteExtraction) -> AgentExtraction {
        AgentExtraction(
            tags: extraction.tags,
            entities: extraction.entities.map {
                AgentExtractedEntity(name: $0.name, kind: $0.kind, excerpt: $0.excerpt)
            },
            actionItems: extraction.actionItems,
            summary: extraction.summary
        )
    }
}
