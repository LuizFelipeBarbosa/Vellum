import Foundation

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
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = outputFormatting
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
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
