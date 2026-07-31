import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class PageReordererTests: XCTestCase {
    func testMovingFirstPageToSecondTranslatesStrokeByOnePageHeight() throws {
        let original = makeStroke(
            locations: [
                CGPoint(x: 20, y: 80),
                CGPoint(x: 60, y: 120),
            ]
        )
        let drawing = PKDrawing(strokes: [original])

        let result = PageReorderer.movePages(
            source: IndexSet(integer: 0),
            to: 2,
            drawing: drawing,
            elements: [],
            pages: makePages(count: 2),
            geometry: .a4
        )

        let moved = try XCTUnwrap(result.drawing.strokes.first)
        let expectedTransform = original.transform.concatenating(
            CGAffineTransform(translationX: 0, y: PageGeometry.a4.pageHeight)
        )
        XCTAssertEqual(
            moved.transform,
            expectedTransform
        )
    }

    func testBoundaryStraddlingStrokeMovesWholeWithItsMidpointBand() throws {
        let original = makeStroke(
            locations: [
                CGPoint(x: 20, y: PageGeometry.a4.pageHeight - 40),
                CGPoint(x: 60, y: PageGeometry.a4.pageHeight + 100),
            ],
            size: CGSize(width: 16, height: 16)
        )
        XCTAssertLessThan(original.renderBounds.minY, PageGeometry.a4.pageHeight)
        XCTAssertGreaterThan(original.renderBounds.midY, PageGeometry.a4.pageHeight)

        let result = PageReorderer.movePages(
            source: IndexSet(integer: 1),
            to: 0,
            drawing: PKDrawing(strokes: [original]),
            elements: [],
            pages: makePages(count: 2),
            geometry: .a4
        )

        let moved = try XCTUnwrap(result.drawing.strokes.first)
        let expectedTransform = original.transform.concatenating(
            CGAffineTransform(translationX: 0, y: -PageGeometry.a4.pageHeight)
        )
        XCTAssertEqual(
            moved.transform,
            expectedTransform
        )
    }

    func testElementUsesEffectiveBoundingBoxBandAndMovesVertically() throws {
        let element = makeElement(
            frame: CanvasRect(
                x: 90,
                y: Double(PageGeometry.a4.pageHeight + 60),
                width: 120,
                height: 80
            ),
            rotation: .pi / 8
        )

        let result = PageReorderer.movePages(
            source: IndexSet(integer: 1),
            to: 0,
            drawing: PKDrawing(),
            elements: [element],
            pages: makePages(count: 2),
            geometry: .a4
        )

        let moved = try XCTUnwrap(result.elements.first)
        XCTAssertEqual(moved.frame.x, element.frame.x, accuracy: 0.001)
        XCTAssertEqual(
            moved.frame.y,
            element.frame.y - Double(PageGeometry.a4.pageHeight),
            accuracy: 0.001
        )
        XCTAssertEqual(moved.rotation, element.rotation, accuracy: 0.001)
    }

    func testPagesPermuteAndAttachmentIsNormalizedOntoNewFirstRow() {
        let attachmentElement = makeElement(
            frame: CanvasRect(x: 20, y: 30, width: 40, height: 50)
        )
        let firstID = UUID()
        let secondID = UUID()
        let pages = [
            makePage(
                id: firstID,
                order: 0,
                path: "pages/attachment/drawing.data",
                text: "attachment",
                background: .ruled,
                elements: [attachmentElement]
            ),
            makePage(
                id: secondID,
                order: 1,
                path: "pages/second/drawing.data",
                text: "second",
                background: .grid
            ),
        ]

        let result = PageReorderer.movePages(
            source: IndexSet(integer: 0),
            to: 2,
            drawing: PKDrawing(),
            elements: [attachmentElement],
            pages: pages,
            geometry: .a4
        )

        XCTAssertEqual(result.pages.map(\.id), [secondID, firstID])
        XCTAssertEqual(result.pages.map(\.order), [0, 1])
        XCTAssertEqual(result.pages[0].drawingAssetPath, pages[0].drawingAssetPath)
        XCTAssertEqual(result.pages[0].plainText, pages[0].plainText)
        XCTAssertEqual(result.pages[0].elements, pages[0].elements)
        XCTAssertEqual(result.pages[0].background, pages[1].background)
        XCTAssertTrue(result.pages[1].drawingAssetPath.hasPrefix("pages/"))
        XCTAssertTrue(result.pages[1].drawingAssetPath.hasSuffix("/drawing.data"))
        XCTAssertNotEqual(result.pages[1].drawingAssetPath, pages[0].drawingAssetPath)
        XCTAssertEqual(
            result.pages[1].drawingAssetPath,
            "pages/\(result.pages[1].id.uuidString)/drawing.data"
        )
        XCTAssertEqual(result.pages[1].plainText, "")
        XCTAssertTrue(result.pages[1].elements.isEmpty)
        XCTAssertEqual(Set(result.pages.map(\.id)), Set(pages.map(\.id)))
    }

    func testAttachmentIsUntouchedWhenOriginalFirstPageStaysFirst() {
        let pages = makePages(count: 3)

        let result = PageReorderer.movePages(
            source: IndexSet(integer: 2),
            to: 1,
            drawing: PKDrawing(),
            elements: [],
            pages: pages,
            geometry: .a4
        )

        XCTAssertEqual(result.pages.map(\.id), [pages[0].id, pages[2].id, pages[1].id])
        XCTAssertEqual(result.pages.map(\.order), [0, 1, 2])
        assertPage(result.pages[0], equals: pages[0])
    }

    func testNoOpMovePreservesEveryInputValue() {
        let stroke = makeStroke(
            locations: [
                CGPoint(x: 10, y: PageGeometry.a4.pageHeight + 20),
                CGPoint(x: 30, y: PageGeometry.a4.pageHeight + 40),
            ]
        )
        let element = makeElement(
            frame: CanvasRect(x: 10, y: 30, width: 40, height: 50)
        )
        let pages = makePages(count: 5)
        let drawing = PKDrawing(strokes: [stroke])

        let result = PageReorderer.movePages(
            source: IndexSet([1, 2]),
            to: 3,
            drawing: drawing,
            elements: [element],
            pages: pages,
            geometry: .a4
        )

        XCTAssertEqual(
            result.drawing.dataRepresentation(),
            drawing.dataRepresentation()
        )
        XCTAssertEqual(result.elements, [element])
        assertPages(result.pages, equal: pages)
    }

    func testLetterGeometryTranslatesStrokeAndElementByLetterPageHeight() throws {
        let geometry = PageGeometry(portraitAspectRatio: 792.0 / 612.0)
        let stroke = makeStroke(
            locations: [
                CGPoint(x: 20, y: 80),
                CGPoint(x: 60, y: 120),
            ]
        )
        let element = makeElement(
            frame: CanvasRect(x: 20, y: 40, width: 100, height: 80)
        )

        let result = PageReorderer.movePages(
            source: IndexSet(integer: 0),
            to: 2,
            drawing: PKDrawing(strokes: [stroke]),
            elements: [element],
            pages: makePages(count: 2),
            geometry: geometry
        )

        let movedStroke = try XCTUnwrap(result.drawing.strokes.first)
        XCTAssertEqual(
            movedStroke.transform,
            stroke.transform.concatenating(
                CGAffineTransform(translationX: 0, y: geometry.pageHeight)
            )
        )
        let movedElement = try XCTUnwrap(result.elements.first)
        XCTAssertEqual(
            movedElement.frame.y,
            element.frame.y + Double(geometry.pageHeight),
            accuracy: 0.001
        )
        XCTAssertNotEqual(geometry.pageHeight, PageGeometry.a4.pageHeight)
    }

    private func makeStroke(
        locations: [CGPoint],
        size: CGSize = CGSize(width: 4, height: 4)
    ) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.1,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
    }

    private func makeElement(
        frame: CanvasRect,
        rotation: Double = 0
    ) -> CanvasElement {
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: "assets/image.jpg",
                    originalPixelSize: CanvasSize(width: 100, height: 100)
                )
            ),
            frame: frame,
            rotation: rotation
        )
    }

    private func makePages(count: Int) -> [NotePage] {
        (0..<count).map { index in
            makePage(
                id: UUID(),
                order: index,
                path: "pages/\(index)/drawing.data",
                text: "page \(index)",
                background: index.isMultiple(of: 2) ? .blank : .ruled
            )
        }
    }

    private func makePage(
        id: UUID,
        order: Int,
        path: String,
        text: String,
        background: PageBackground,
        elements: [CanvasElement] = []
    ) -> NotePage {
        NotePage(
            id: id,
            order: order,
            plainText: text,
            drawingAssetPath: path,
            background: background,
            elements: elements
        )
    }

    private func assertPages(
        _ actual: [NotePage],
        equal expected: [NotePage],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualPage, expectedPage) in zip(actual, expected) {
            assertPage(actualPage, equals: expectedPage, file: file, line: line)
        }
    }

    private func assertPage(
        _ actual: NotePage,
        equals expected: NotePage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.order, expected.order, file: file, line: line)
        XCTAssertEqual(actual.plainText, expected.plainText, file: file, line: line)
        XCTAssertEqual(
            actual.drawingAssetPath,
            expected.drawingAssetPath,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.background, expected.background, file: file, line: line)
        XCTAssertEqual(actual.pdfPage, expected.pdfPage, file: file, line: line)
        XCTAssertEqual(actual.elements, expected.elements, file: file, line: line)
    }
}
