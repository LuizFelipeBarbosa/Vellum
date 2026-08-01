import Foundation
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
        guard let data = try? VellumJSONCoding.encoder().encode(payload) else { return false }
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
        return try? VellumJSONCoding.decoder().decode(SelectionPasteboardPayload.self, from: data)
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
}
