import Foundation

public struct HeuristicVellumAgent: VellumAgent, Sendable {
    public init() {}

    public func analyze(
        event: WorkspaceEvent,
        context: AgentContext
    ) async throws -> [AgentProposal] {
        let text = context.canonicalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        var proposals: [AgentProposal] = []
        if text.contains("TODO") || text.range(of: "task", options: .caseInsensitive) != nil {
            let trigger = text.contains("TODO") ? "TODO" : "task"
            proposals.append(
                proposal(
                    context: context,
                    title: "Tag as task",
                    explanation: "The note contains the \(trigger) trigger.",
                    confidence: 0.9,
                    operation: .addTag("task")
                )
            )
        }

        let trimmedTitle = context.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty || trimmedTitle == "Untitled" {
            proposals.append(
                proposal(
                    context: context,
                    title: "Suggest a title",
                    explanation: "The note does not yet have a descriptive title.",
                    confidence: 0.7,
                    operation: .suggestTitle(TitleSuggestion.firstSentence(from: text))
                )
            )
        }

        if text.count > 80 {
            proposals.append(
                proposal(
                    context: context,
                    title: "Create a summary",
                    explanation: "The note is long enough to benefit from a concise summary.",
                    confidence: 0.6,
                    operation: .createSummary(String(text.prefix(200)))
                )
            )
        }

        // Confidence values are fixed so mock output remains reproducible across runs.
        if context.currentSpaceID == nil,
           let matchingSpace = context.spaces.first(where: {
               text.range(of: $0.name, options: .caseInsensitive) != nil
           }) {
            proposals.append(
                proposal(
                    context: context,
                    title: "File to \(matchingSpace.name)",
                    explanation: "The note mentions the \(matchingSpace.name) space.",
                    confidence: 0.85,
                    operation: .fileToSpace(
                        spaceName: matchingSpace.name,
                        color: matchingSpace.color
                    )
                )
            )
        }

        var proposedTargetIDs: Set<UUID> = []
        let otherNotes = context.otherNotes.sorted {
            StableOrder.ascending($0, $1, by: \.title, tiebreak: \.id)
        }
        for candidate in otherNotes
        where proposedTargetIDs.count < 3
            && candidate.title.count >= 4
            && text.range(of: candidate.title, options: .caseInsensitive) != nil
            && !proposedTargetIDs.contains(candidate.id) {
            proposedTargetIDs.insert(candidate.id)
            proposals.append(
                proposal(
                    context: context,
                    title: "Link \(candidate.title)",
                    explanation: "The note mentions '\(candidate.title)'.",
                    confidence: 0.75,
                    operation: .linkNotes(targetNoteID: candidate.id, kind: .mention)
                )
            )
        }

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("TODO")
                || trimmed.hasPrefix("- [ ]")
                || trimmed.range(of: "follow up", options: .caseInsensitive) != nil {
                proposals.append(
                    proposal(
                        context: context,
                        title: "Extract task",
                        explanation: "The line contains an actionable task.",
                        confidence: 0.8,
                        operation: .extractTask(text: trimmed, pageID: nil)
                    )
                )
            }
        }

        let pattern = try NSRegularExpression(pattern: "[A-Z][a-z]+ [A-Z][a-z]+")
        let stopwords: Set<String> = [
            "the", "this", "that", "these", "those", "a", "an", "it", "there", "we", "you", "they",
        ]
        var matchedEntities: [String: String] = [:]
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for match in pattern.matches(in: line, range: range) {
                guard let matchRange = Range(match.range, in: line) else { continue }
                let name = String(line[matchRange])
                let words = name.split(separator: " ").map { $0.lowercased() }
                guard !words.contains(where: stopwords.contains), matchedEntities[name] == nil else {
                    continue
                }
                matchedEntities[name] = line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for name in matchedEntities.keys.sorted() {
            proposals.append(
                proposal(
                    context: context,
                    title: "Extract \(name)",
                    explanation: "The text contains a capitalized person name.",
                    confidence: 0.65,
                    operation: .extractEntity(
                        name: name,
                        kind: .person,
                        pageID: nil,
                        excerpt: matchedEntities[name]
                    )
                )
            )
        }
        return proposals
    }

    private func proposal(
        context: AgentContext,
        title: String,
        explanation: String,
        confidence: Double,
        operation: AgentOperation
    ) -> AgentProposal {
        AgentProposal(
            id: UUID(),
            noteID: context.noteID,
            basedOnRevision: context.noteRevision,
            createdAt: Date(),
            title: title,
            explanation: explanation,
            confidence: confidence,
            operation: operation,
            status: .pending
        )
    }
}
