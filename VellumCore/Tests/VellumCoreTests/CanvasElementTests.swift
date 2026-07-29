import Foundation
import Testing
@testable import VellumCore

@Test("A text canvas element round trips through JSON")
func textCanvasElementRoundTrip() throws {
    let original = CanvasElement(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        content: .text(
            TextBoxContent(
                text: "A thought in the margin",
                fontSize: 18,
                color: CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
            )
        ),
        frame: CanvasRect(x: 12, y: 24, width: 240, height: 80),
        rotation: 0.25,
        createdAt: Date(timeIntervalSince1970: 1_234.567)
    )

    let data = try FilePersistence.encoder().encode(original)
    let decoded = try FilePersistence.decoder().decode(CanvasElement.self, from: data)

    #expect(decoded == original)
}

@Test("An image canvas element round trips through JSON")
func imageCanvasElementRoundTrip() throws {
    let original = CanvasElement(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        content: .image(
            ImageContent(
                assetPath: "assets/22222222-2222-2222-2222-222222222222.jpg",
                originalPixelSize: CanvasSize(width: 4_032, height: 3_024)
            )
        ),
        frame: CanvasRect(x: 32, y: 48, width: 320, height: 240),
        rotation: -0.5,
        createdAt: Date(timeIntervalSince1970: 2_345.678)
    )

    let data = try FilePersistence.encoder().encode(original)
    let decoded = try FilePersistence.decoder().decode(CanvasElement.self, from: data)

    #expect(decoded == original)
}

@Test("An unknown canvas element kind and payload are preserved losslessly")
func unknownCanvasElementKind() throws {
    let data = Data(
        """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "kind": "video",
          "video": {
            "assetPath": "assets/clip.mov",
            "autoplay": true,
            "duration": 12.5,
            "chapters": ["intro", null]
          },
          "frame": { "x": 0, "y": 0, "width": 100, "height": 100 },
          "rotation": 0,
          "createdAt": "1970-01-01T00:00:01.000Z"
        }
        """.utf8
    )
    let expectedPayload = JSONValue.object([
        "assetPath": .string("assets/clip.mov"),
        "autoplay": .bool(true),
        "duration": .number(12.5),
        "chapters": .array([.string("intro"), .null]),
    ])

    let element = try FilePersistence.decoder().decode(CanvasElement.self, from: data)
    let reencoded = try FilePersistence.encoder().encode(element)
    let originalJSON = try FilePersistence.decoder().decode(JSONValue.self, from: data)
    let reencodedJSON = try FilePersistence.decoder().decode(JSONValue.self, from: reencoded)

    #expect(element.content == .unknown(UnknownContent(kind: "video", payload: expectedPayload)))
    #expect(reencodedJSON == originalJSON)
}

@Test("Note page decoding preserves unknown canvas elements and z-order")
func notePageDecodingPreservesUnknownElements() throws {
    let data = Data(
        """
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "order": 0,
          "plainText": "Canvas page",
          "drawingAssetPath": "pages/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA/drawing.data",
          "background": "blank",
          "elements": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "kind": "text",
              "text": {
                "text": "First",
                "fontSize": 16,
                "color": { "red": 0.1, "green": 0.2, "blue": 0.3, "alpha": 1 }
              },
              "frame": { "x": 1, "y": 2, "width": 100, "height": 40 },
              "rotation": 0.1,
              "createdAt": "1970-01-01T00:00:01.000Z"
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "kind": "video",
              "video": { "assetPath": "assets/clip.mov", "muted": false },
              "frame": { "x": 0, "y": 0, "width": 1, "height": 1 },
              "rotation": 0,
              "createdAt": "1970-01-01T00:00:02.000Z"
            },
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "kind": "image",
              "image": {
                "assetPath": "assets/photo.jpg",
                "originalPixelSize": { "width": 1200, "height": 800 }
              },
              "frame": { "x": 3, "y": 4, "width": 300, "height": 200 },
              "rotation": -0.2,
              "createdAt": "1970-01-01T00:00:03.000Z"
            }
          ]
        }
        """.utf8
    )
    let expected = [
        CanvasElement(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            content: .text(
                TextBoxContent(
                    text: "First",
                    fontSize: 16,
                    color: CodableColor(red: 0.1, green: 0.2, blue: 0.3)
                )
            ),
            frame: CanvasRect(x: 1, y: 2, width: 100, height: 40),
            rotation: 0.1,
            createdAt: Date(timeIntervalSince1970: 1)
        ),
        CanvasElement(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            content: .unknown(
                UnknownContent(
                    kind: "video",
                    payload: .object([
                        "assetPath": .string("assets/clip.mov"),
                        "muted": .bool(false),
                    ])
                )
            ),
            frame: CanvasRect(x: 0, y: 0, width: 1, height: 1),
            rotation: 0,
            createdAt: Date(timeIntervalSince1970: 2)
        ),
        CanvasElement(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            content: .image(
                ImageContent(
                    assetPath: "assets/photo.jpg",
                    originalPixelSize: CanvasSize(width: 1_200, height: 800)
                )
            ),
            frame: CanvasRect(x: 3, y: 4, width: 300, height: 200),
            rotation: -0.2,
            createdAt: Date(timeIntervalSince1970: 3)
        ),
    ]

    let page = try FilePersistence.decoder().decode(NotePage.self, from: data)
    let roundTrippedPage = try FilePersistence.decoder().decode(
        NotePage.self,
        from: FilePersistence.encoder().encode(page)
    )

    #expect(page.elements == expected)
    #expect(roundTrippedPage.elements == expected)
}

@Test("Malformed known canvas elements fail direct and note page decoding")
func malformedKnownCanvasElementFailsDecoding() throws {
    let malformedElement =
        """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "kind": "text",
          "text": 42,
          "frame": { "x": 0, "y": 0, "width": 100, "height": 40 },
          "rotation": 0,
          "createdAt": "1970-01-01T00:00:02.000Z"
        }
        """
    let elementData = Data(malformedElement.utf8)
    let pageData = Data(
        """
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "order": 0,
          "plainText": "Corrupt canvas page",
          "drawingAssetPath": "pages/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA/drawing.data",
          "background": "blank",
          "elements": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "kind": "image",
              "image": {
                "assetPath": "assets/photo.jpg",
                "originalPixelSize": { "width": 1200, "height": 800 }
              },
              "frame": { "x": 3, "y": 4, "width": 300, "height": 200 },
              "rotation": 0,
              "createdAt": "1970-01-01T00:00:01.000Z"
            },
            \(malformedElement)
          ]
        }
        """.utf8
    )

    #expect(throws: DecodingError.self) {
        try FilePersistence.decoder().decode(CanvasElement.self, from: elementData)
    }
    #expect(throws: DecodingError.self) {
        try FilePersistence.decoder().decode(NotePage.self, from: pageData)
    }
}

@Test("A note page without an elements key decodes with an empty canvas")
func notePageWithoutElementsDefaultsToEmpty() throws {
    let data = Data(
        """
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "order": 0,
          "plainText": "Legacy page",
          "drawingAssetPath": "pages/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA/drawing.data",
          "background": "ruled"
        }
        """.utf8
    )

    let page = try FilePersistence.decoder().decode(NotePage.self, from: data)

    #expect(page.elements == [])
}

@Test("Image flip state and layer placement round trip through JSON")
func imageFlipStateAndLayerPlacementRoundTrip() throws {
    let original = CanvasElement(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        content: .image(
            ImageContent(
                assetPath: "assets/flipped-image.jpg",
                originalPixelSize: CanvasSize(width: 3_000, height: 2_000),
                flippedHorizontally: true,
                flippedVertically: true
            )
        ),
        frame: CanvasRect(x: 15, y: 25, width: 300, height: 200),
        rotation: 0.75,
        createdAt: Date(timeIntervalSince1970: 4_567.89),
        layerPlacement: .aboveInk
    )

    let data = try FilePersistence.encoder().encode(original)
    let decoded = try FilePersistence.decoder().decode(CanvasElement.self, from: data)

    #expect(decoded == original)
}

@Test("Legacy image JSON defaults missing flip state and layer placement")
func legacyImageJSONDefaultsNewFields() throws {
    let data = Data(
        """
        {
          "id": "55555555-5555-5555-5555-555555555555",
          "kind": "image",
          "image": {
            "assetPath": "assets/legacy-photo.jpg",
            "originalPixelSize": { "width": 1600, "height": 900 }
          },
          "frame": { "x": 20, "y": 30, "width": 320, "height": 180 },
          "rotation": -0.25,
          "createdAt": "1970-01-01T00:00:05.000Z"
        }
        """.utf8
    )

    let element = try FilePersistence.decoder().decode(CanvasElement.self, from: data)

    #expect(element.layerPlacement == nil)
    guard case .image(let image) = element.content else {
        Issue.record("Expected decoded legacy image content.")
        return
    }
    #expect(image.flippedHorizontally == false)
    #expect(image.flippedVertically == false)
}

@Test("An unrecognized layer placement decodes as absent")
func unrecognizedLayerPlacementDefaultsToNil() throws {
    let data = Data(
        """
        {
          "id": "66666666-6666-6666-6666-666666666666",
          "kind": "text",
          "text": {
            "text": "Future placement",
            "fontSize": 18,
            "color": { "red": 0.2, "green": 0.4, "blue": 0.6, "alpha": 1 }
          },
          "frame": { "x": 5, "y": 10, "width": 200, "height": 60 },
          "rotation": 0,
          "createdAt": "1970-01-01T00:00:06.000Z",
          "layerPlacement": "insideInk"
        }
        """.utf8
    )

    let element = try FilePersistence.decoder().decode(CanvasElement.self, from: data)

    #expect(element.layerPlacement == nil)
}

@Test("Encoding an absent layer placement omits its JSON key")
func absentLayerPlacementIsNotEncoded() throws {
    let element = CanvasElement(
        id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
        content: .text(
            TextBoxContent(
                text: "No explicit placement",
                fontSize: 14,
                color: CodableColor(red: 0.3, green: 0.5, blue: 0.7)
            )
        ),
        frame: CanvasRect(x: 1, y: 2, width: 180, height: 50),
        createdAt: Date(timeIntervalSince1970: 7)
    )

    let data = try FilePersistence.encoder().encode(element)
    let json = try FilePersistence.decoder().decode(JSONValue.self, from: data)

    guard case .object(let object) = json else {
        Issue.record("Expected an encoded JSON object.")
        return
    }
    #expect(object["layerPlacement"] == nil)
}
