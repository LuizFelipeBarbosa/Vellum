import Foundation
import PencilKit
import UIKit
import UniformTypeIdentifiers
import VellumCore

struct SelectionPasteboardPayload: Codable {
    var drawingData: Data
    var elements: [CanvasElement]
    var imageAssets: [String: Data]
}

enum SelectionPasteboard {
    static let pasteboardType = "com.luiz.vellum.canvas-selection"

    @MainActor
    static func write(_ payload: SelectionPasteboardPayload) -> Bool {
        guard let data = try? encoder().encode(payload) else { return false }
        UIPasteboard.general.setData(data, forPasteboardType: pasteboardType)
        return true
    }

    @MainActor
    static func read() -> SelectionPasteboardPayload? {
        guard let data = UIPasteboard.general.data(forPasteboardType: pasteboardType) else {
            return nil
        }
        return try? decoder().decode(SelectionPasteboardPayload.self, from: data)
    }

    @MainActor
    static var hasPayload: Bool {
        UIPasteboard.general.contains(pasteboardTypes: [pasteboardType])
    }

    @MainActor
    static var hasSystemImage: Bool {
        UIPasteboard.general.hasImages
    }

    @MainActor
    static func readSystemImageData() -> Data? {
        let candidateTypes = [
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.heic.identifier,
        ]
        for type in candidateTypes {
            if let data = UIPasteboard.general.data(forPasteboardType: type) {
                return data
            }
        }
        return UIPasteboard.general.image?.jpegData(compressionQuality: 0.9)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private static func decoder() -> JSONDecoder {
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
