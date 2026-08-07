import Foundation
import Testing
@testable import VellumCore

@Test("A legacy note reference defaults its missing preview")
func legacyNoteRefDefaultsPreview() throws {
    let original = LegacyNoteRef(id: UUID(), title: "Legacy")
    let data = try VellumJSONCoding.encoder().encode(original)

    let decoded = try VellumJSONCoding.decoder().decode(NoteRef.self, from: data)

    #expect(decoded == NoteRef(id: original.id, title: original.title))
    #expect(decoded.preview.isEmpty)
}

@Test("A note reference round trips its preview")
func noteRefRoundTripsPreview() throws {
    let original = NoteRef(id: UUID(), title: "Reference", preview: "Preview text")
    let data = try VellumJSONCoding.encoder().encode(original)

    let decoded = try VellumJSONCoding.decoder().decode(NoteRef.self, from: data)

    #expect(decoded == original)
}

@Test("A legacy agent context defaults missing knowledge fields")
func legacyAgentContextDefaultsKnowledgeFields() throws {
    let original = LegacyAgentContext(
        noteID: UUID(),
        noteRevision: 7,
        title: "Legacy context",
        canonicalText: "Stored text",
        currentSpaceID: nil,
        spaces: [],
        otherNotes: [LegacyNoteRef(id: UUID(), title: "Other")]
    )
    let data = try VellumJSONCoding.encoder().encode(original)

    let decoded = try VellumJSONCoding.decoder().decode(AgentContext.self, from: data)

    #expect(decoded.noteID == original.noteID)
    #expect(decoded.noteRevision == original.noteRevision)
    #expect(decoded.title == original.title)
    #expect(decoded.canonicalText == original.canonicalText)
    #expect(decoded.otherNotes == [
        NoteRef(id: original.otherNotes[0].id, title: original.otherNotes[0].title),
    ])
    #expect(decoded.existingTags.isEmpty)
    #expect(decoded.existingLinkTargetIDs.isEmpty)
    #expect(decoded.existingEntityNames.isEmpty)
}

@Test("An agent context round trips enriched knowledge fields")
func agentContextRoundTripsKnowledgeFields() throws {
    let space = Space(
        id: UUID(),
        name: "Research",
        color: .purple,
        createdAt: Date(timeIntervalSince1970: 1)
    )
    let linkTargetIDs = [UUID(), UUID()]
    let original = AgentContext(
        noteID: UUID(),
        noteRevision: 8,
        title: "Enriched context",
        canonicalText: "Canonical text",
        currentSpaceID: space.id,
        spaces: [space],
        otherNotes: [NoteRef(id: UUID(), title: "Other", preview: "A preview")],
        existingTags: ["swift", "design"],
        existingLinkTargetIDs: linkTargetIDs,
        existingEntityNames: ["Vellum", "Swift"]
    )
    let data = try VellumJSONCoding.encoder().encode(original)

    let decoded = try VellumJSONCoding.decoder().decode(AgentContext.self, from: data)

    #expect(decoded.noteID == original.noteID)
    #expect(decoded.noteRevision == original.noteRevision)
    #expect(decoded.title == original.title)
    #expect(decoded.canonicalText == original.canonicalText)
    #expect(decoded.currentSpaceID == original.currentSpaceID)
    #expect(decoded.spaces == original.spaces)
    #expect(decoded.otherNotes == original.otherNotes)
    #expect(decoded.existingTags == original.existingTags)
    #expect(decoded.existingLinkTargetIDs == original.existingLinkTargetIDs)
    #expect(decoded.existingEntityNames == original.existingEntityNames)
}

private struct LegacyNoteRef: Codable {
    let id: UUID
    let title: String
}

private struct LegacyAgentContext: Codable {
    let noteID: UUID
    let noteRevision: Int
    let title: String
    let canonicalText: String
    let currentSpaceID: UUID?
    let spaces: [Space]
    let otherNotes: [LegacyNoteRef]
}
