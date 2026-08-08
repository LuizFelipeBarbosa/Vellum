import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct NoteExtraction {
    @Guide(
        description: "At most 4 short lowercase tag phrases grounded in the note.",
        .maximumCount(4)
    )
    var tags: [String]

    @Guide(
        description: "At most 5 entities explicitly present in the note.",
        .maximumCount(5)
    )
    var entities: [ExtractedEntity]

    @Guide(
        description: "At most 4 concrete action items explicitly stated in the note.",
        .maximumCount(4)
    )
    var actionItems: [String]

    @Guide(description: "1-2 sentence summary of the note")
    var summary: String
}

@available(iOS 26.0, *)
@Generable
struct ExtractedEntity {
    @Guide(description: "The entity name exactly as grounded in the note.")
    var name: String

    @Guide(
        description: "person, topic, or document",
        .anyOf(["person", "topic", "document"])
    )
    var kind: String

    @Guide(description: "A short quote from the note grounding this entity.")
    var excerpt: String
}

@available(iOS 26.0, *)
@Generable
struct OrganizeSuggestion {
    @Guide(
        description: "An existing space name that fits this note, or a short new space name if nothing existing fits. Omit/nil if nothing fits."
    )
    var spaceName: String?

    @Guide(
        description: "1-based indices into the numbered candidate list of at most 3 notes related to this one, most relevant first.",
        .maximumCount(3),
        .element(.range(1...10))
    )
    var relatedNoteOrdinals: [Int]
}
