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

@Test("CodableColor round trips through JSON")
func codableColorJSONRoundTrip() throws {
    let original = CodableColor(red: 0.125, green: 0.5, blue: 0.875, alpha: 0.625)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(CodableColor.self, from: data)

    #expect(decoded == original)
}

@Test("CodableColor emits uppercase hex strings")
func codableColorHexStringIsUppercase() {
    #expect(CodableColor(hex: "d07b3a").hexString == "#D07B3A")
}
