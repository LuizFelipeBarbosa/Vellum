import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

@Test("An open two-vertex shape canvas element round trips through JSON")
func straightLineShapeCanvasElementRoundTrip() throws {
    let original = makeShapeElement(
        id: "44444444-4444-4444-4444-444444444444",
        geometry: .polyline(
            vertices: [
                CanvasPoint(x: 0, y: 0.5),
                CanvasPoint(x: 1, y: 0.5),
            ],
            isClosed: false
        ),
        frame: CanvasRect(x: 12, y: 24, width: 200, height: 40),
        rotation: 0.2,
        strokeColor: CodableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4),
        strokeWidth: 3
    )

    try expectRoundTrip(original)
}

@Test("A closed four-vertex shape canvas element round trips through JSON")
func polygonShapeCanvasElementRoundTrip() throws {
    let original = makeShapeElement(
        id: "55555555-5555-5555-5555-555555555555",
        geometry: .polyline(
            vertices: [
                CanvasPoint(x: 0, y: 0),
                CanvasPoint(x: 1, y: 0),
                CanvasPoint(x: 1, y: 1),
                CanvasPoint(x: 0, y: 1),
            ],
            isClosed: true
        ),
        frame: CanvasRect(x: -20, y: 16, width: 120, height: 80),
        rotation: -.pi / 6,
        strokeColor: CodableColor(red: 0.8, green: 0.6, blue: 0.4),
        strokeWidth: 5.5
    )

    try expectRoundTrip(original)
}

@Test("An open three-vertex shape canvas element round trips through JSON")
func openPolylineShapeCanvasElementRoundTrip() throws {
    let original = makeShapeElement(
        id: "66666666-6666-6666-6666-666666666666",
        geometry: .polyline(
            vertices: [
                CanvasPoint(x: -0.05, y: 0.1),
                CanvasPoint(x: 0.5, y: 0.9),
                CanvasPoint(x: 1.05, y: 0.2),
            ],
            isClosed: false
        ),
        frame: CanvasRect(x: 40, y: 60, width: 240, height: 160),
        rotation: .pi / 8,
        strokeColor: CodableColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.9),
        strokeWidth: 2.25
    )

    try expectRoundTrip(original)
}

@Test("An ellipse shape canvas element round trips through JSON")
func ellipseShapeCanvasElementRoundTrip() throws {
    let original = makeShapeElement(
        id: "77777777-7777-7777-7777-777777777777",
        geometry: .ellipse,
        frame: CanvasRect(x: 8, y: 12, width: 96, height: 64),
        rotation: -0.75,
        strokeColor: CodableColor(red: 0.9, green: 0.1, blue: 0.2),
        strokeWidth: 1.5
    )

    try expectRoundTrip(original)
}

@Test("An unrecognized shape geometry type is preserved as unknown content")
func unrecognizedShapeGeometryTypeIsPreserved() throws {
    let data = Data(
        """
        {
          "id": "88888888-8888-8888-8888-888888888888",
          "kind": "shape",
          "shape": {
            "type": "star",
            "points": 5,
            "innerRadius": 0.45,
            "strokeColor": { "red": 1, "green": 0.5, "blue": 0, "alpha": 1 },
            "strokeWidth": 4
          },
          "frame": { "x": 10, "y": 20, "width": 100, "height": 80 },
          "rotation": 0.25,
          "createdAt": "1970-01-01T00:00:08.000Z"
        }
        """.utf8
    )
    let expectedPayload = JSONValue.object([
        "type": .string("star"),
        "points": .integer(5),
        "innerRadius": .number(0.45),
        "strokeColor": .object([
            "red": .integer(1),
            "green": .number(0.5),
            "blue": .integer(0),
            "alpha": .integer(1),
        ]),
        "strokeWidth": .integer(4),
    ])

    let element = try FilePersistence.decoder().decode(CanvasElement.self, from: data)
    let reencoded = try FilePersistence.encoder().encode(element)
    let originalJSON = try FilePersistence.decoder().decode(JSONValue.self, from: data)
    let reencodedJSON = try FilePersistence.decoder().decode(JSONValue.self, from: reencoded)

    #expect(element.content == .unknown(UnknownContent(kind: "shape", payload: expectedPayload)))
    #expect(reencodedJSON == originalJSON)
}

@Test("A malformed shape payload decodes as unknown content")
func malformedShapePayloadDecodesAsUnknown() throws {
    let data = Data(
        """
        {
          "id": "99999999-9999-9999-9999-999999999999",
          "kind": "shape",
          "shape": {
            "type": "polyline",
            "isClosed": false,
            "strokeColor": { "red": 0, "green": 0, "blue": 0, "alpha": 1 },
            "strokeWidth": 2
          },
          "frame": { "x": 0, "y": 0, "width": 100, "height": 50 },
          "rotation": 0,
          "createdAt": "1970-01-01T00:00:09.000Z"
        }
        """.utf8
    )
    let expectedPayload = JSONValue.object([
        "type": .string("polyline"),
        "isClosed": .bool(false),
        "strokeColor": .object([
            "red": .integer(0),
            "green": .integer(0),
            "blue": .integer(0),
            "alpha": .integer(1),
        ]),
        "strokeWidth": .integer(2),
    ])

    let element = try FilePersistence.decoder().decode(CanvasElement.self, from: data)

    #expect(element.content == .unknown(UnknownContent(kind: "shape", payload: expectedPayload)))
}

@Test("ShapeGeometry denormalizes polyline vertices into content coordinates")
func shapeGeometryDenormalizesPolylineVertices() {
    let content = ShapeContent(
        geometry: .polyline(
            vertices: [
                CanvasPoint(x: 0, y: 0),
                CanvasPoint(x: 0.25, y: 0.5),
                CanvasPoint(x: 1, y: 1),
            ],
            isClosed: false
        ),
        strokeColor: CodableColor(red: 0, green: 0, blue: 0),
        strokeWidth: 2
    )
    let vertices = ShapeGeometry.unrotatedVertices(
        for: content,
        in: CanvasRect(x: 10, y: 20, width: 200, height: 100)
    )
    let expected = [
        CGPoint(x: 10, y: 20),
        CGPoint(x: 60, y: 70),
        CGPoint(x: 210, y: 120),
    ]

    #expect(vertices.count == expected.count)
    for (actual, expected) in zip(vertices, expected) {
        #expect(abs(actual.x - expected.x) < 0.0001)
        #expect(abs(actual.y - expected.y) < 0.0001)
    }
}

@Test("ShapeGeometry rotates a path around the frame center")
func shapeGeometryRotatesPathAroundFrameCenter() {
    let content = ShapeContent(
        geometry: .polyline(
            vertices: [
                CanvasPoint(x: 0, y: 0.5),
                CanvasPoint(x: 1, y: 0.5),
            ],
            isClosed: false
        ),
        strokeColor: CodableColor(red: 0, green: 0, blue: 0),
        strokeWidth: 2
    )
    let path = ShapeGeometry.path(
        for: content,
        in: CanvasRect(x: 10, y: 20, width: 100, height: 40),
        rotation: .pi / 2
    )
    let bounds = path.boundingBoxOfPath

    #expect(abs(bounds.minX - 60) < 0.0001)
    #expect(abs(bounds.minY - (-10)) < 0.0001)
    #expect(abs(bounds.width) < 0.0001)
    #expect(abs(bounds.height - 100) < 0.0001)
}

@Test("ShapeGeometry creates an unrotated ellipse inscribed in its frame")
func shapeGeometryCreatesEllipseInFrame() {
    let content = ShapeContent(
        geometry: .ellipse,
        strokeColor: CodableColor(red: 0, green: 0, blue: 0),
        strokeWidth: 2
    )
    let frame = CanvasRect(x: 12, y: 34, width: 160, height: 90)
    let bounds = ShapeGeometry.path(for: content, in: frame, rotation: 0).boundingBoxOfPath

    #expect(abs(bounds.minX - 12) < 0.0001)
    #expect(abs(bounds.minY - 34) < 0.0001)
    #expect(abs(bounds.width - 160) < 0.0001)
    #expect(abs(bounds.height - 90) < 0.0001)
}

private func makeShapeElement(
    id: String,
    geometry: ShapeContent.Geometry,
    frame: CanvasRect,
    rotation: Double,
    strokeColor: CodableColor,
    strokeWidth: Double
) -> CanvasElement {
    CanvasElement(
        id: UUID(uuidString: id)!,
        content: .shape(
            ShapeContent(
                geometry: geometry,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth
            )
        ),
        frame: frame,
        rotation: rotation,
        createdAt: Date(timeIntervalSince1970: 4_000)
    )
}

private func expectRoundTrip(_ original: CanvasElement) throws {
    let data = try FilePersistence.encoder().encode(original)
    let decoded = try FilePersistence.decoder().decode(CanvasElement.self, from: data)

    #expect(decoded == original)
}
