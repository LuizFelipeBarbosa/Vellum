import Foundation
import VellumCore

struct AgentExtraction: Sendable {
    let tags: [String]
    let entities: [AgentExtractedEntity]
    let actionItems: [String]
    let summary: String

    init(
        tags: [String] = [],
        entities: [AgentExtractedEntity] = [],
        actionItems: [String] = [],
        summary: String = ""
    ) {
        self.tags = tags
        self.entities = entities
        self.actionItems = actionItems
        self.summary = summary
    }

    static let empty = AgentExtraction()
}

struct AgentExtractedEntity: Sendable {
    let name: String
    let kind: String
    let excerpt: String

    init(name: String, kind: String, excerpt: String) {
        self.name = name
        self.kind = kind
        self.excerpt = excerpt
    }
}

struct AgentOrganizeSuggestion: Sendable {
    let spaceName: String?
    let relatedNoteOrdinals: [Int]

    init(spaceName: String?, relatedNoteOrdinals: [Int]) {
        self.spaceName = spaceName
        self.relatedNoteOrdinals = relatedNoteOrdinals
    }
}

enum AgentProposalBuilder {
    private enum Confidence {
        static let tag = 0.7
        static let entity = 0.65
        static let task = 0.6
        static let summary = 0.6
        static let fileToSpace = 0.55
        static let link = 0.6
    }

    private enum Cap {
        static let tags = 4
        static let entities = 5
        static let tasks = 4
        static let links = 3
    }

    private static let newSpaceColor = SpaceColor.blue

    static func proposals(
        extraction: AgentExtraction,
        organize: AgentOrganizeSuggestion?,
        rankedCandidates: [NoteRef],
        context: AgentContext
    ) -> [AgentProposal] {
        var proposals: [AgentProposal] = []

        let existingTags = Set(context.existingTags.map { comparisonKey($0) })
        var seenTags: Set<String> = []
        var addedTagCount = 0
        for rawTag in extraction.tags {
            guard addedTagCount < Cap.tags else { break }

            let tag = trimmed(rawTag)
            let key = comparisonKey(tag)
            guard !tag.isEmpty,
                  !existingTags.contains(key),
                  seenTags.insert(key).inserted else {
                continue
            }

            proposals.append(
                proposal(
                    context: context,
                    title: "Add tag '\(tag)'",
                    explanation: "The note discusses \(tag).",
                    confidence: Confidence.tag,
                    operation: .addTag(tag)
                )
            )
            addedTagCount += 1
        }

        let existingEntityNames = Set(
            context.existingEntityNames.map { comparisonKey($0) }
        )
        var addedEntityCount = 0
        for extractedEntity in extraction.entities {
            guard addedEntityCount < Cap.entities else { break }

            let name = trimmed(extractedEntity.name)
            guard !name.isEmpty,
                  !existingEntityNames.contains(comparisonKey(name)) else {
                continue
            }

            let kind = entityKind(from: extractedEntity.kind)
            let excerpt = trimmed(extractedEntity.excerpt)
            proposals.append(
                proposal(
                    context: context,
                    title: "Extract \(name)",
                    explanation: "The note identifies \(name) as a \(kind.rawValue).",
                    confidence: Confidence.entity,
                    operation: .extractEntity(
                        name: name,
                        kind: kind,
                        pageID: nil,
                        excerpt: excerpt.isEmpty ? nil : excerpt
                    )
                )
            )
            addedEntityCount += 1
        }

        var addedTaskCount = 0
        for rawActionItem in extraction.actionItems {
            guard addedTaskCount < Cap.tasks else { break }

            let actionItem = trimmed(rawActionItem)
            guard !actionItem.isEmpty else { continue }

            proposals.append(
                proposal(
                    context: context,
                    title: "Extract task",
                    explanation: "The note includes the action item '\(actionItem)'.",
                    confidence: Confidence.task,
                    operation: .extractTask(text: actionItem, pageID: nil)
                )
            )
            addedTaskCount += 1
        }

        let canonicalText = trimmed(context.canonicalText)
        let summary = trimmed(extraction.summary)
        if canonicalText.count > 300, !summary.isEmpty {
            proposals.append(
                proposal(
                    context: context,
                    title: "Create summary",
                    explanation: "The note is long enough to benefit from a concise summary.",
                    confidence: Confidence.summary,
                    operation: .createSummary(summary)
                )
            )
        }

        if context.currentSpaceID == nil,
           let suggestedSpaceName = organize?.spaceName {
            let spaceName = strippingListPrefix(trimmed(suggestedSpaceName))
            if !spaceName.isEmpty {
                let existingSpace = context.spaces.first {
                    comparisonKey($0.name) == comparisonKey(spaceName)
                }
                let resolvedName = existingSpace?.name ?? spaceName
                let color = existingSpace?.color ?? newSpaceColor
                proposals.append(
                    proposal(
                        context: context,
                        title: "File to \(resolvedName)",
                        explanation: "This note fits the \(resolvedName) space.",
                        confidence: Confidence.fileToSpace,
                        operation: .fileToSpace(spaceName: resolvedName, color: color)
                    )
                )
            }
        }

        var proposedTargetIDs: Set<UUID> = []
        for ordinal in organize?.relatedNoteOrdinals ?? [] {
            guard proposedTargetIDs.count < Cap.links else { break }
            guard ordinal > 0, ordinal <= rankedCandidates.count else { continue }

            let target = rankedCandidates[ordinal - 1]
            guard target.id != context.noteID,
                  !context.existingLinkTargetIDs.contains(target.id),
                  proposedTargetIDs.insert(target.id).inserted else {
                continue
            }

            proposals.append(
                proposal(
                    context: context,
                    title: "Link \(target.title)",
                    explanation: "This note is related to '\(target.title)'.",
                    confidence: Confidence.link,
                    operation: .linkNotes(targetNoteID: target.id, kind: .related)
                )
            )
        }

        return proposals
    }

    private static func proposal(
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

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func comparisonKey(_ value: String) -> String {
        trimmed(value).lowercased()
    }

    /// Drops a leading "1. " / "2) " list marker the model sometimes echoes
    /// back when it answers with a list entry instead of a bare name.
    private static func strippingListPrefix(_ value: String) -> String {
        guard let range = value.range(
            of: #"^\d+[.)]\s*"#,
            options: .regularExpression
        ) else {
            return value
        }
        return String(value[range.upperBound...])
    }

    private static func entityKind(from value: String) -> EntityKind {
        switch comparisonKey(value) {
        case EntityKind.person.rawValue:
            return .person
        case EntityKind.document.rawValue:
            return .document
        case EntityKind.topic.rawValue:
            return .topic
        default:
            return .topic
        }
    }
}
