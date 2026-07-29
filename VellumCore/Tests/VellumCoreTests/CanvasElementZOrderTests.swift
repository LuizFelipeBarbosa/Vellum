import Foundation
import Testing
@testable import VellumCore

@Test("Legacy z-order normalization preserves relative order within kind bands")
func legacyZOrderNormalization() {
    let text1 = makeZOrderTextElement("text-1")
    let image1 = makeZOrderImageElement("image-1")
    let text2 = makeZOrderTextElement("text-2")
    let shape1 = makeZOrderShapeElement()
    let image2 = makeZOrderImageElement("image-2")

    #expect(
        [text1, shape1, image1].zOrderNormalized()
            == [image1, shape1, text1]
    )
    #expect(
        [text1, image1, text2, shape1, image2].zOrderNormalized()
            == [image1, image2, shape1, text1, text2]
    )
}

@Test("Any explicit placement prevents legacy z-order normalization")
func explicitPlacementPreventsLegacyNormalization() {
    let elements = [
        makeZOrderTextElement("text"),
        makeZOrderImageElement("image", layerPlacement: .aboveInk),
        makeZOrderShapeElement(),
    ]

    #expect(elements.zOrderNormalized() == elements)
}

@Test("Effective z-order is a stable partition around the ink layer")
func effectiveZOrderStablePartition() {
    let aboveImage = makeZOrderImageElement("above-image", layerPlacement: .aboveInk)
    let belowText = makeZOrderTextElement("below-text", layerPlacement: .belowInk)
    let aboveText = makeZOrderTextElement("above-text")
    let belowImage = makeZOrderImageElement("below-image")
    let elements = [aboveImage, belowText, aboveText, belowImage]

    #expect(
        elements.sortedByEffectiveZ()
            == [belowText, belowImage, aboveImage, aboveText]
    )
}

@Test("Effective placement uses kind defaults when placement is absent")
func effectivePlacementKindDefaults() {
    let text = makeZOrderTextElement("text")
    let image = makeZOrderImageElement("image")
    let shape = makeZOrderShapeElement()
    let unknown = makeZOrderUnknownElement()

    #expect(text.layerPlacement == nil)
    #expect(image.layerPlacement == nil)
    #expect(shape.layerPlacement == nil)
    #expect(unknown.layerPlacement == nil)
    #expect(text.effectivePlacement == .aboveInk)
    #expect(image.effectivePlacement == .belowInk)
    #expect(shape.effectivePlacement == .belowInk)
    #expect(unknown.effectivePlacement == .belowInk)
}

@Test("Explicit placement overrides the content kind default")
func explicitPlacementOverridesKindDefault() {
    let image = makeZOrderImageElement("image", layerPlacement: .aboveInk)
    let text = makeZOrderTextElement("text", layerPlacement: .belowInk)

    #expect(image.effectivePlacement == .aboveInk)
    #expect(text.effectivePlacement == .belowInk)
}

private func makeZOrderTextElement(
    _ text: String,
    layerPlacement: LayerPlacement? = nil
) -> CanvasElement {
    CanvasElement(
        content: .text(
            TextBoxContent(
                text: text,
                fontSize: 16,
                color: CodableColor(red: 0.1, green: 0.2, blue: 0.3)
            )
        ),
        frame: CanvasRect(x: 0, y: 0, width: 100, height: 40),
        layerPlacement: layerPlacement
    )
}

private func makeZOrderImageElement(
    _ assetName: String,
    layerPlacement: LayerPlacement? = nil
) -> CanvasElement {
    CanvasElement(
        content: .image(
            ImageContent(
                assetPath: "assets/\(assetName).jpg",
                originalPixelSize: CanvasSize(width: 1_200, height: 800)
            )
        ),
        frame: CanvasRect(x: 10, y: 20, width: 120, height: 80),
        layerPlacement: layerPlacement
    )
}

private func makeZOrderShapeElement(
    layerPlacement: LayerPlacement? = nil
) -> CanvasElement {
    CanvasElement(
        content: .shape(
            ShapeContent(
                geometry: .ellipse,
                strokeColor: CodableColor(red: 0.4, green: 0.5, blue: 0.6),
                strokeWidth: 2
            )
        ),
        frame: CanvasRect(x: 20, y: 30, width: 80, height: 80),
        layerPlacement: layerPlacement
    )
}

private func makeZOrderUnknownElement(
    layerPlacement: LayerPlacement? = nil
) -> CanvasElement {
    CanvasElement(
        content: .unknown(
            UnknownContent(
                kind: "video",
                payload: .object(["assetPath": .string("assets/video.mov")])
            )
        ),
        frame: CanvasRect(x: 30, y: 40, width: 160, height: 90),
        layerPlacement: layerPlacement
    )
}
