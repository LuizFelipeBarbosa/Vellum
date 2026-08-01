import Foundation
import Testing
@testable import VellumCore

@Test("CodableColor parses prefixed and bare hex strings")
func codableColorParsesHexStrings() {
    let prefixed = CodableColor(hex: "#9A6B35")
    let bare = CodableColor(hex: "9A6B35")

    #expect(prefixed == bare)
    #expect(prefixed.hexString == "#9A6B35")
}

@Test("CodableColor falls back to black for invalid hex strings")
func codableColorInvalidHexFallsBackToBlack() {
    let color = CodableColor(hex: "not-a-color", alpha: 0.4)

    #expect(color == CodableColor(red: 0, green: 0, blue: 0, alpha: 0.4))
    #expect(color.hexString == "#000000")
}

/// Every element colour in every note manifest is written through this encoder, so the
/// four key names are on-disk format. Decoding is left to the synthesized conformance;
/// what needs guarding is that a property rename cannot quietly orphan saved colours.
@Test("CodableColor persists its components under stable JSON keys")
func codableColorJSONKeysAreStable() throws {
    let data = try JSONEncoder().encode(
        CodableColor(red: 0.125, green: 0.5, blue: 0.875, alpha: 0.625)
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Double]
    )

    #expect(object == [
        "red": 0.125,
        "green": 0.5,
        "blue": 0.875,
        "alpha": 0.625,
    ])
}

@Test("CodableColor emits uppercase hex strings")
func codableColorHexStringIsUppercase() {
    #expect(CodableColor(hex: "d07b3a").hexString == "#D07B3A")
}
