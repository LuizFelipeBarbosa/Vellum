import Foundation
import Testing
@testable import VellumCore

@Test("A note summary round trips its tags")
func noteSummaryRoundTripsTags() throws {
    let original = NoteSummary(
        id: UUID(),
        title: "Tagged note",
        noteType: .pdf,
        spaceID: UUID(),
        previewText: "A useful preview",
        hasInk: true,
        linkCount: 2,
        tags: ["work", "urgent"],
        updatedAt: Date(timeIntervalSince1970: 1_234.5)
    )
    let data = try VellumJSONCoding.encoder().encode(original)

    let decoded = try VellumJSONCoding.decoder().decode(NoteSummary.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.title == original.title)
    #expect(decoded.noteType == original.noteType)
    #expect(decoded.spaceID == original.spaceID)
    #expect(decoded.previewText == original.previewText)
    #expect(decoded.hasInk == original.hasInk)
    #expect(decoded.linkCount == original.linkCount)
    #expect(decoded.tags == original.tags)
    #expect(decoded.updatedAt == original.updatedAt)
}

@Test("A legacy note summary defaults its missing tags")
func legacyNoteSummaryDefaultsTags() throws {
    let id = UUID()
    let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Legacy note",
          "noteType": "note",
          "spaceID": null,
          "previewText": "Stored preview",
          "hasInk": false,
          "linkCount": 1,
          "updatedAt": "1970-01-01T00:20:34.000Z"
        }
        """
    let data = try #require(json.data(using: .utf8))

    let decoded = try VellumJSONCoding.decoder().decode(NoteSummary.self, from: data)

    #expect(decoded.id == id)
    #expect(decoded.title == "Legacy note")
    #expect(decoded.noteType == .note)
    #expect(decoded.spaceID == nil)
    #expect(decoded.previewText == "Stored preview")
    #expect(!decoded.hasInk)
    #expect(decoded.linkCount == 1)
    #expect(decoded.tags == [])
    #expect(decoded.updatedAt == Date(timeIntervalSince1970: 1_234))
}
