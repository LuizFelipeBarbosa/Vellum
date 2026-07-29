import Foundation
@testable import Vellum
import VellumCore
import XCTest

final class ElementTapHitTesterTests: XCTestCase {
    func testTapOutsideImageReturnsNil() {
        let image = makeImage(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 80)
        )

        let result = ElementTapHitTester.hitTest(
            elements: [image],
            at: CGPoint(x: 40, y: 40),
            minimumHitWidth: 4,
            extraRadius: 0
        )

        XCTAssertNil(result)
    }

    func testTapInsideUnrotatedImageReturnsImage() {
        let image = makeImage(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 80)
        )

        let result = ElementTapHitTester.hitTest(
            elements: [image],
            at: CGPoint(x: 150, y: 130),
            minimumHitWidth: 4,
            extraRadius: 0
        )

        XCTAssertEqual(result?.id, image.id)
    }

    func testTapInsideRotatedImageOutsideUnrotatedFrameReturnsImage() {
        let image = makeImage(
            frame: CanvasRect(x: 100, y: 100, width: 100, height: 40),
            rotation: .pi / 4
        )
        // Rotating the in-frame point (110, 110) by 45 degrees lands near (129, 85),
        // above the unrotated frame but inside the rotated image.
        let result = ElementTapHitTester.hitTest(
            elements: [image],
            at: CGPoint(x: 129, y: 85),
            minimumHitWidth: 4,
            extraRadius: 0
        )

        XCTAssertEqual(result?.id, image.id)
    }

    func testTapInsideRotatedImageAABBButOutsideImageReturnsNil() {
        let image = makeImage(
            frame: CanvasRect(x: 100, y: 100, width: 100, height: 40),
            rotation: .pi / 4
        )
        // This point sits in the rotated frame's upper-left AABB corner, beyond the
        // actual rotated rectangle.
        let point = CGPoint(x: 105, y: 75)
        XCTAssertTrue(image.rotatedBoundingBox.contains(point))

        let result = ElementTapHitTester.hitTest(
            elements: [image],
            at: point,
            minimumHitWidth: 4,
            extraRadius: 0
        )

        XCTAssertNil(result)
    }

    func testLastOverlappingImageWinsWithinLegacyBand() {
        let frame = CanvasRect(x: 100, y: 100, width: 100, height: 40)
        let firstImage = makeImage(frame: frame)
        let secondImage = makeImage(frame: frame)
        let sharedPoint = CGPoint(x: 150, y: 120)

        let result = ElementTapHitTester.hitTest(
            elements: [firstImage, secondImage],
            at: sharedPoint,
            minimumHitWidth: 4,
            extraRadius: 12
        )

        XCTAssertEqual(result?.id, secondImage.id)
    }

    func testLegacyShapeWinsOverImageRegardlessOfArrayOrder() {
        let frame = CanvasRect(x: 100, y: 100, width: 100, height: 40)
        let image = makeImage(frame: frame)
        let shape = makePolylineShape(frame: frame)
        let sharedPoint = CGPoint(x: 150, y: 120)

        let imageThenShape = ElementTapHitTester.hitTest(
            elements: [image, shape],
            at: sharedPoint,
            minimumHitWidth: 4,
            extraRadius: 12
        )
        let shapeThenImage = ElementTapHitTester.hitTest(
            elements: [shape, image],
            at: sharedPoint,
            minimumHitWidth: 4,
            extraRadius: 12
        )

        XCTAssertEqual(imageThenShape?.id, shape.id)
        XCTAssertEqual(shapeThenImage?.id, shape.id)
    }

    func testAboveInkImageWinsOverLaterBelowInkImage() {
        let frame = CanvasRect(x: 100, y: 100, width: 100, height: 40)
        let aboveInkImage = makeImage(
            frame: frame,
            layerPlacement: .aboveInk
        )
        let belowInkImage = makeImage(
            frame: frame,
            layerPlacement: .belowInk
        )

        let result = ElementTapHitTester.hitTest(
            elements: [aboveInkImage, belowInkImage],
            at: CGPoint(x: 150, y: 120),
            minimumHitWidth: 4,
            extraRadius: 12
        )

        XCTAssertEqual(result?.id, aboveInkImage.id)
    }

    func testTapInsideTextReturnsNil() {
        let text = makeText(
            frame: CanvasRect(x: 100, y: 100, width: 120, height: 40)
        )

        let result = ElementTapHitTester.hitTest(
            elements: [text],
            at: CGPoint(x: 150, y: 120),
            minimumHitWidth: 4,
            extraRadius: 12
        )

        XCTAssertNil(result)
    }

    private func makeImage(
        frame: CanvasRect,
        rotation: Double = 0,
        layerPlacement: LayerPlacement? = nil
    ) -> CanvasElement {
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: "assets/test.jpg",
                    originalPixelSize: CanvasSize(width: 1200, height: 800)
                )
            ),
            frame: frame,
            rotation: rotation,
            layerPlacement: layerPlacement
        )
    }

    private func makePolylineShape(frame: CanvasRect) -> CanvasElement {
        CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .polyline(
                        vertices: [
                            CanvasPoint(x: 0, y: 0.5),
                            CanvasPoint(x: 1, y: 0.5),
                        ],
                        isClosed: false
                    ),
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 4
                )
            ),
            frame: frame
        )
    }

    private func makeText(frame: CanvasRect) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Text",
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame
        )
    }
}
