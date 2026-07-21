import Foundation
import Testing
@testable import VellumCore

@Test("JSON integers round trip without losing precision")
func jsonIntegersRoundTripLosslessly() throws {
    let data = Data(
        """
        {
          "largeSigned": 9007199254740993,
          "int64Min": -9223372036854775808,
          "uint64Max": 18446744073709551615,
          "decimal": 12.5,
          "nested": [
            9007199254740993,
            { "minimum": -9223372036854775808, "decimal": 12.5 },
            18446744073709551615
          ]
        }
        """.utf8
    )
    let expected = JSONValue.object([
        "largeSigned": .integer(9_007_199_254_740_993),
        "int64Min": .integer(.min),
        "uint64Max": .unsignedInteger(.max),
        "decimal": .number(12.5),
        "nested": .array([
            .integer(9_007_199_254_740_993),
            .object([
                "minimum": .integer(.min),
                "decimal": .number(12.5),
            ]),
            .unsignedInteger(.max),
        ]),
    ])

    let decoded = try FilePersistence.decoder().decode(JSONValue.self, from: data)
    let reencoded = try FilePersistence.encoder().encode(decoded)
    let roundTripped = try FilePersistence.decoder().decode(JSONValue.self, from: reencoded)
    let reencodedJSON = String(decoding: reencoded, as: UTF8.self)

    #expect(decoded == expected)
    #expect(roundTripped == decoded)
    #expect(reencodedJSON.contains("9007199254740993"))
    #expect(reencodedJSON.contains("-9223372036854775808"))
    #expect(reencodedJSON.contains("18446744073709551615"))
    #expect(!reencodedJSON.contains("9007199254740993.0"))
}
