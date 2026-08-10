import Foundation

/// Carries one configured `ISO8601DateFormatter` into a coder's `@Sendable` date-strategy
/// closure. The unchecked conformance is sound because each instance is created inside a single
/// `encoder()`/`decoder()` call and captured by that coder's closure alone — it is never shared
/// between coders, so no two threads can reach the same formatter. This deliberately does not
/// rely on `ISO8601DateFormatter` being thread-safe, which Apple does not document.
private struct CoderDateFormatter: @unchecked Sendable {
    private let formatter: ISO8601DateFormatter

    init(_ options: ISO8601DateFormatter.Options) {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
    }

    func string(from date: Date) -> String { formatter.string(from: date) }

    func date(from value: String) -> Date? { formatter.date(from: value) }
}

/// The one JSON date contract Vellum writes and reads: ISO 8601 with fractional seconds, decoding
/// plain ISO 8601 too so older payloads still load. Every path that persists or transfers model
/// values — note packages, activity logs, the canvas pasteboard — must go through here, because a
/// divergence silently corrupts element timestamps as they cross between them.
public enum VellumJSONCoding {
    /// - Parameter outputFormatting: defaults to none, matching `JSONEncoder`'s own default.
    public static func encoder(
        outputFormatting: JSONEncoder.OutputFormatting = []
    ) -> JSONEncoder {
        let encoder = JSONEncoder()
        // Built once per encoder rather than inside the strategy closure: constructing an
        // ISO8601DateFormatter is expensive, and the closure runs once per Date encoded —
        // a cost that scales with element count on every autosave.
        let fractionalSecondsFormatter = CoderDateFormatter([.withInternetDateTime, .withFractionalSeconds])
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalSecondsFormatter.string(from: date))
        }
        encoder.outputFormatting = outputFormatting
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let fractionalSecondsFormatter = CoderDateFormatter([.withInternetDateTime, .withFractionalSeconds])
        let plainFormatter = CoderDateFormatter([.withInternetDateTime])
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = fractionalSecondsFormatter.date(from: value) {
                return date
            }

            guard let date = plainFormatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO 8601 date string."
                )
            }
            return date
        }
        return decoder
    }
}
