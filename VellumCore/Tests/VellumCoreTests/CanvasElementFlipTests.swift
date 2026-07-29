import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

@Test("A horizontal image flip reflects its center and toggles horizontal state")
func horizontalImageFlip() {
    let original = CanvasElement(
        content: .image(
            ImageContent(
                assetPath: "assets/horizontal.jpg",
                originalPixelSize: CanvasSize(width: 1_200, height: 800)
            )
        ),
        frame: CanvasRect(x: 10, y: 20, width: 40, height: 30),
        rotation: 0.35
    )
    let pivot = CGPoint(x: 100, y: 75)

    let flipped = original.flipped(horizontal: true, aboutPivot: pivot)

    expectApproximatelyEqual(centerX(of: flipped.frame), 2 * Double(pivot.x) - centerX(of: original.frame))
    expectApproximatelyEqual(centerY(of: flipped.frame), centerY(of: original.frame))
    expectApproximatelyEqual(flipped.frame.width, original.frame.width)
    expectApproximatelyEqual(flipped.frame.height, original.frame.height)
    expectApproximatelyEqual(flipped.rotation, -original.rotation)
    guard case .image(let image) = flipped.content else {
        Issue.record("Expected image content after flipping.")
        return
    }
    #expect(image.flippedHorizontally)
    #expect(image.flippedVertically == false)
}

@Test("A vertical image flip reflects its center and toggles vertical state")
func verticalImageFlip() {
    let original = CanvasElement(
        content: .image(
            ImageContent(
                assetPath: "assets/vertical.jpg",
                originalPixelSize: CanvasSize(width: 900, height: 1_600)
            )
        ),
        frame: CanvasRect(x: 24, y: 36, width: 80, height: 120),
        rotation: -0.6
    )
    let pivot = CGPoint(x: 15, y: 250)

    let flipped = original.flipped(horizontal: false, aboutPivot: pivot)

    expectApproximatelyEqual(centerX(of: flipped.frame), centerX(of: original.frame))
    expectApproximatelyEqual(centerY(of: flipped.frame), 2 * Double(pivot.y) - centerY(of: original.frame))
    expectApproximatelyEqual(flipped.frame.width, original.frame.width)
    expectApproximatelyEqual(flipped.frame.height, original.frame.height)
    expectApproximatelyEqual(flipped.rotation, -original.rotation)
    guard case .image(let image) = flipped.content else {
        Issue.record("Expected image content after flipping.")
        return
    }
    #expect(image.flippedHorizontally == false)
    #expect(image.flippedVertically)
}

@Test("Two horizontal flips about the same pivot restore an image element")
func doubleHorizontalFlipRestoresElement() {
    let original = CanvasElement(
        content: .image(
            ImageContent(
                assetPath: "assets/double-flip.png",
                originalPixelSize: CanvasSize(width: 640, height: 480)
            )
        ),
        frame: CanvasRect(x: -12, y: 48, width: 125, height: 75),
        rotation: 0.4
    )
    let pivot = CGPoint(x: 37.5, y: -20)

    let restored = original
        .flipped(horizontal: true, aboutPivot: pivot)
        .flipped(horizontal: true, aboutPivot: pivot)

    expectFramesApproximatelyEqual(restored.frame, original.frame)
    expectApproximatelyEqual(restored.rotation, original.rotation)
    #expect(restored.content == original.content)
}

@Test("Horizontal then vertical shape flips rotate world vertices by pi about the pivot")
func horizontalThenVerticalPolylineFlip() {
    let original = polylineElement(
        vertices: [
            CanvasPoint(x: 0.1, y: 0.2),
            CanvasPoint(x: 0.8, y: 0.35),
            CanvasPoint(x: 0.45, y: 0.9),
        ],
        frame: CanvasRect(x: 20, y: 45, width: 160, height: 90),
        rotation: 0.55
    )
    let pivot = CGPoint(x: 230, y: 25)

    let flipped = original
        .flipped(horizontal: true, aboutPivot: pivot)
        .flipped(horizontal: false, aboutPivot: pivot)
    let expectedWorldVertices = worldVertices(of: original).map { vertex in
        CanvasPoint(
            x: 2 * Double(pivot.x) - vertex.x,
            y: 2 * Double(pivot.y) - vertex.y
        )
    }

    expectVertices(worldVertices(of: flipped), near: expectedWorldVertices)
}

@Test("A horizontal shape flip reflects every rotated world vertex")
func horizontalPolylineFlipReflectsWorldVertices() {
    let original = polylineElement(
        vertices: [
            CanvasPoint(x: 0.05, y: 0.15),
            CanvasPoint(x: 0.65, y: 0.25),
            CanvasPoint(x: 0.9, y: 0.8),
        ],
        frame: CanvasRect(x: -30, y: 70, width: 210, height: 130),
        rotation: -0.72
    )
    let pivot = CGPoint(x: 145, y: 300)

    let flipped = original.flipped(horizontal: true, aboutPivot: pivot)
    let expectedWorldVertices = worldVertices(of: original).map { vertex in
        CanvasPoint(x: 2 * Double(pivot.x) - vertex.x, y: vertex.y)
    }

    expectVertices(worldVertices(of: flipped), near: expectedWorldVertices)
}

@Test("Flipping an ellipse preserves its geometry")
func ellipseFlipPreservesGeometry() {
    let original = CanvasElement(
        content: .shape(
            ShapeContent(
                geometry: .ellipse,
                strokeColor: CodableColor(red: 0.1, green: 0.4, blue: 0.7),
                strokeWidth: 3
            )
        ),
        frame: CanvasRect(x: 40, y: 60, width: 120, height: 80),
        rotation: 0.3
    )
    let pivot = CGPoint(x: -15, y: 210)

    let flipped = original.flipped(horizontal: false, aboutPivot: pivot)

    expectApproximatelyEqual(centerX(of: flipped.frame), centerX(of: original.frame))
    expectApproximatelyEqual(centerY(of: flipped.frame), 2 * Double(pivot.y) - centerY(of: original.frame))
    expectApproximatelyEqual(flipped.rotation, -original.rotation)
    #expect(flipped.content == original.content)
    guard case .shape(let shape) = flipped.content, case .ellipse = shape.geometry else {
        Issue.record("Expected unchanged ellipse geometry after flipping.")
        return
    }
}

@Test("Flipping text moves its frame without mirroring its content")
func textFlipPreservesContent() {
    let original = CanvasElement(
        content: .text(
            TextBoxContent(
                text: "Readable after reflection",
                fontSize: 22,
                color: CodableColor(red: 0.2, green: 0.3, blue: 0.4)
            )
        ),
        frame: CanvasRect(x: 35, y: 25, width: 240, height: 70),
        rotation: -0.25
    )
    let pivot = CGPoint(x: 300, y: 80)

    let flipped = original.flipped(horizontal: true, aboutPivot: pivot)

    expectApproximatelyEqual(centerX(of: flipped.frame), 2 * Double(pivot.x) - centerX(of: original.frame))
    expectApproximatelyEqual(centerY(of: flipped.frame), centerY(of: original.frame))
    expectApproximatelyEqual(flipped.rotation, -original.rotation)
    #expect(flipped.content == original.content)
}

@Test("Flipping preserves element identity, creation date, and layer placement")
func flipPreservesElementMetadata() {
    let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let createdAt = Date(timeIntervalSince1970: 12_345.678)
    let original = CanvasElement(
        id: id,
        content: .image(
            ImageContent(
                assetPath: "assets/metadata.jpg",
                originalPixelSize: CanvasSize(width: 2_000, height: 1_000)
            )
        ),
        frame: CanvasRect(x: 10, y: 20, width: 300, height: 150),
        rotation: 0.15,
        createdAt: createdAt,
        layerPlacement: .aboveInk
    )

    let flipped = original.flipped(
        horizontal: true,
        aboutPivot: CGPoint(x: 75, y: 125)
    )

    #expect(flipped.id == id)
    #expect(flipped.createdAt == createdAt)
    #expect(flipped.layerPlacement == .aboveInk)
}

private let flipTolerance = 1e-9

private func polylineElement(
    vertices: [CanvasPoint],
    frame: CanvasRect,
    rotation: Double
) -> CanvasElement {
    CanvasElement(
        content: .shape(
            ShapeContent(
                geometry: .polyline(vertices: vertices, isClosed: true),
                strokeColor: CodableColor(red: 0.8, green: 0.2, blue: 0.5),
                strokeWidth: 4
            )
        ),
        frame: frame,
        rotation: rotation
    )
}

private func worldVertices(of element: CanvasElement) -> [CanvasPoint] {
    guard case .shape(let shape) = element.content,
          case .polyline(let vertices, _) = shape.geometry else {
        Issue.record("Expected a polyline shape element.")
        return []
    }

    let centerX = centerX(of: element.frame)
    let centerY = centerY(of: element.frame)
    let cosine = cos(element.rotation)
    let sine = sin(element.rotation)
    return vertices.map { vertex in
        let unrotatedX = element.frame.x + vertex.x * element.frame.width
        let unrotatedY = element.frame.y + vertex.y * element.frame.height
        let offsetX = unrotatedX - centerX
        let offsetY = unrotatedY - centerY
        return CanvasPoint(
            x: centerX + offsetX * cosine - offsetY * sine,
            y: centerY + offsetX * sine + offsetY * cosine
        )
    }
}

private func centerX(of frame: CanvasRect) -> Double {
    frame.x + frame.width / 2
}

private func centerY(of frame: CanvasRect) -> Double {
    frame.y + frame.height / 2
}

private func expectFramesApproximatelyEqual(_ actual: CanvasRect, _ expected: CanvasRect) {
    expectApproximatelyEqual(actual.x, expected.x)
    expectApproximatelyEqual(actual.y, expected.y)
    expectApproximatelyEqual(actual.width, expected.width)
    expectApproximatelyEqual(actual.height, expected.height)
}

private func expectVertices(_ actual: [CanvasPoint], near expected: [CanvasPoint]) {
    #expect(actual.count == expected.count)
    guard actual.count == expected.count else { return }

    for (actualVertex, expectedVertex) in zip(actual, expected) {
        expectApproximatelyEqual(actualVertex.x, expectedVertex.x)
        expectApproximatelyEqual(actualVertex.y, expectedVertex.y)
    }
}

private func expectApproximatelyEqual(_ actual: Double, _ expected: Double) {
    #expect(abs(actual - expected) < flipTolerance)
}
