import Foundation
import Testing
@testable import VellumCore

@Test("A kind-only style uses the default spacing and dynamic paper tint")
func kindOnlyStyleUsesDefaults() {
    let style = PageBackgroundStyle(kind: .ruled)

    #expect(style.spacing == 24)
    #expect(style.paperTint == nil)
}

@Test("The legacy style preserves the pre-migration dotted background")
func legacyStylePreservesDottedBackground() {
    #expect(
        PageBackgroundStyle.legacyDefault
            == PageBackgroundStyle(kind: .dots, spacing: 24, paperTint: nil)
    )
}

@Test("Style initialization clamps spacing to the supported range")
func styleInitializationClampsSpacing() {
    #expect(PageBackgroundStyle(kind: .grid, spacing: 8).spacing == 16)
    #expect(PageBackgroundStyle(kind: .grid, spacing: 200).spacing == 48)
}

@Test("Style decoding clamps spacing to the supported range", arguments: [
    (8.0, 16.0),
    (200.0, 48.0),
])
func styleDecodingClampsSpacing(spacing: Double, expected: Double) throws {
    let data = Data("{\"kind\":\"grid\",\"spacing\":\(spacing)}".utf8)

    let style = try JSONDecoder().decode(PageBackgroundStyle.self, from: data)

    #expect(style.spacing == expected)
}

@Test("A style round trips with a paper tint")
func styleRoundTripPreservesPaperTint() throws {
    let style = PageBackgroundStyle(
        kind: .ruled,
        spacing: 32,
        paperTint: CodableColor(hex: "#FAF3DC")
    )

    let decoded = try JSONDecoder().decode(
        PageBackgroundStyle.self,
        from: JSONEncoder().encode(style)
    )

    #expect(decoded == style)
}

@Test("A nil paper tint is omitted from encoded JSON")
func nilPaperTintIsOmittedFromJSON() throws {
    let data = try JSONEncoder().encode(PageBackgroundStyle(kind: .blank))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["paperTint"] == nil)
}

@Test("An unknown style kind decodes to blank")
func unknownStyleKindDecodesToBlank() throws {
    let data = Data("{\"kind\":\"hexagons\",\"spacing\":24}".utf8)

    let style = try JSONDecoder().decode(PageBackgroundStyle.self, from: data)

    #expect(style.kind == .blank)
}

@Test("A missing style kind decodes to the legacy dotted kind")
func missingStyleKindDecodesToDots() throws {
    let original = PageBackgroundStyle(kind: .ruled)
    let encoded = try JSONEncoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "kind")
    let data = try JSONSerialization.data(withJSONObject: object)

    let style = try JSONDecoder().decode(PageBackgroundStyle.self, from: data)

    #expect(style.kind == .dots)
}

@Test("Tint luminance selects contrasting pattern ink")
func tintLuminanceSelectsContrastingPatternInk() {
    let belowThreshold = CodableColor(red: 0.499, green: 0.499, blue: 0.499)
    let aboveThreshold = CodableColor(red: 0.501, green: 0.501, blue: 0.501)
    let opacity = 0.35

    #expect(PageBackgroundStyle.isDarkTint(belowThreshold))
    #expect(!PageBackgroundStyle.isDarkTint(aboveThreshold))
    #expect(
        PageBackgroundStyle.patternInk(forTint: aboveThreshold, opacity: opacity)
            == CodableColor(hex: "#26221B", alpha: opacity)
    )
    #expect(
        PageBackgroundStyle.patternInk(forTint: belowThreshold, opacity: opacity)
            == CodableColor(hex: "#E9E3D6", alpha: opacity)
    )
}

@Test("A note resolves its style only for generated page backgrounds")
func noteResolvesStyleForGeneratedBackgrounds() {
    let backgrounds: [PageBackground] = [.blank, .ruled, .grid, .pdf, .image]
    let pages = backgrounds.enumerated().map { index, background in
        let pageID = UUID()
        return NotePage(
            id: pageID,
            order: index,
            plainText: "",
            drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
            background: background
        )
    }
    let style = PageBackgroundStyle(
        kind: .grid,
        spacing: 32,
        paperTint: CodableColor(hex: "#FAF3DC")
    )
    let note = Note(
        id: UUID(),
        schemaVersion: Note.currentSchemaVersion,
        revision: 1,
        title: "Backgrounds",
        tags: [],
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        pages: pages,
        backgroundStyle: style
    )

    #expect(note.resolvedBackgroundStyle(forPageAt: 0) == style)
    #expect(note.resolvedBackgroundStyle(forPageAt: 1) == style)
    #expect(note.resolvedBackgroundStyle(forPageAt: 2) == style)
    #expect(note.resolvedBackgroundStyle(forPageAt: 3) == nil)
    #expect(note.resolvedBackgroundStyle(forPageAt: 4) == nil)
    #expect(note.resolvedBackgroundStyle(forPageAt: -1) == nil)
    #expect(note.resolvedBackgroundStyle(forPageAt: pages.count) == style)
    #expect(note.resolvedBackgroundStyle(forPageAt: pages.count + 1) == style)
}
