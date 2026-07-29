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
        // contains() never prompts; probing foreign pasteboard content with data() raises
        // a paste-permission ask even when this type is absent.
        guard hasPayload,
              let data = UIPasteboard.general.data(forPasteboardType: pasteboardType) else {
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
    static func readSystemImageData() async -> Data? {
        let candidateTypes = [
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.heic.identifier,
        ]
        // contains() never prompts; probing with data() can raise one paste-permission
        // ask per representation, so read only the type the pasteboard declares.
        for type in candidateTypes
        where UIPasteboard.general.contains(pasteboardTypes: [type]) {
            if let data = UIPasteboard.general.data(forPasteboardType: type) {
                return data
            }
        }
        if let data = UIPasteboard.general.image?.jpegData(compressionQuality: 0.9) {
            return data
        }
        for provider in UIPasteboard.general.itemProviders {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                continue
            }
            let data: Data? = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(
                    forTypeIdentifier: UTType.image.identifier
                ) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            if let data {
                return data
            }
        }
        return nil
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
