import CoreGraphics
import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class StrokeHitTesterTests: XCTestCase {
    func testOpenLassoContainsNearbyStrokeAndExcludesDistantStroke() {
        let nearbyStroke = makeStroke(
            locations: [
                CGPoint(x: 10, y: 10),
                CGPoint(x: 20, y: 20),
                CGPoint(x: 30, y: 18),
            ]
        )
        let distantStroke = makeStroke(
            locations: [
                CGPoint(x: 200, y: 200),
                CGPoint(x: 220, y: 220),
            ]
        )
        let drawing = PKDrawing(strokes: [nearbyStroke, distantStroke])
        let lasso = CGMutablePath()
        lasso.move(to: CGPoint(x: -10, y: -10))
        lasso.addLine(to: CGPoint(x: 60, y: -10))
        lasso.addLine(to: CGPoint(x: 25, y: 60))

        let indices = StrokeHitTester.strokeIndices(in: drawing, containedBy: lasso)

        XCTAssertTrue(indices.contains(0))
        XCTAssertFalse(indices.contains(1))
    }

    func testRectHitTestingAppliesStrokeTransform() {
        let translatedStroke = makeStroke(
            locations: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)],
            transform: CGAffineTransform(translationX: 100, y: 100)
        )
        let untranslatedStroke = makeStroke(
            locations: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
        )
        let drawing = PKDrawing(strokes: [translatedStroke, untranslatedStroke])
        let rect = CGRect(x: 95, y: 95, width: 25, height: 25)

        let indices = StrokeHitTester.strokeIndices(in: drawing, intersecting: rect)

        XCTAssertTrue(indices.contains(0))
        XCTAssertFalse(indices.contains(1))
    }

    func testElementRectIntersectionReturnsExpectedSubset() {
        let first = makeElement(frame: CanvasRect(x: 10, y: 10, width: 20, height: 20))
        let second = makeElement(frame: CanvasRect(x: 60, y: 20, width: 20, height: 20))
        let third = makeElement(frame: CanvasRect(x: 120, y: 120, width: 20, height: 20))

        let ids = StrokeHitTester.elementIDs(
            in: [first, second, third],
            intersecting: CGRect(x: 15, y: 15, width: 50, height: 20)
        )

        XCTAssertEqual(ids, Set([first.id, second.id]))
    }

    func testElementLassoUsesCenterAndCorners() {
        let centerInside = makeElement(
            frame: CanvasRect(x: 40, y: 40, width: 20, height: 20)
        )
        let cornerInside = makeElement(
            frame: CanvasRect(x: 90, y: 90, width: 40, height: 40)
        )
        let outside = makeElement(
            frame: CanvasRect(x: 150, y: 150, width: 20, height: 20)
        )
        let lasso = CGMutablePath()
        lasso.addRect(CGRect(x: 0, y: 0, width: 100, height: 100))

        let ids = StrokeHitTester.elementIDs(
            in: [centerInside, cornerInside, outside],
            containedBy: lasso
        )

        XCTAssertEqual(ids, Set([centerInside.id, cornerInside.id]))
    }

    private func makeStroke(
        locations: [CGPoint],
        transform: CGAffineTransform = .identity
    ) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.1,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date()),
            transform: transform
        )
    }

    private func makeElement(frame: CanvasRect) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Selection",
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: frame
        )
    }
}
