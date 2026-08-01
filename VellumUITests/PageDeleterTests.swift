import Foundation
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class PageDeleterTests: XCTestCase {
    func testDeletingMiddlePageRemovesItsContentAndMovesLaterContentUp() {
        let geometries = [
            PageGeometry.a4,
            PageGeometry(portraitAspectRatio: 792.0 / 612.0),
        ]

        for geometry in geometries {
            let firstStroke = CanvasFixtures.makeStroke(
                locations: [
                    CGPoint(x: 20, y: 80),
                    CGPoint(x: 60, y: 120),
                ]
            )
            let deletedStroke = CanvasFixtures.makeStroke(
                locations: [
                    CGPoint(x: 20, y: geometry.pageHeight + 80),
                    CGPoint(x: 60, y: geometry.pageHeight + 120),
                ]
            )
            let laterStroke = CanvasFixtures.makeStroke(
                locations: [
                    CGPoint(x: 20, y: 2 * geometry.pageHeight + 80),
                    CGPoint(x: 60, y: 2 * geometry.pageHeight + 120),
                ]
            )
            let firstElement = CanvasFixtures.makeImageElement(
                frame: CanvasRect(x: 20, y: 60, width: 100, height: 40)
            )
            let deletedElement = CanvasFixtures.makeImageElement(
                frame: CanvasRect(
                    x: 30,
                    y: Double(geometry.pageHeight + 60),
                    width: 100,
                    height: 40
                )
            )
            let laterElement = CanvasFixtures.makeImageElement(
                frame: CanvasRect(
                    x: 40,
                    y: Double(2 * geometry.pageHeight + 60),
                    width: 100,
                    height: 40
                )
            )
            let pages = makePages(count: 3)

            let result = PageDeleter.deletePage(
                at: 1,
                drawing: PKDrawing(
                    strokes: [firstStroke, deletedStroke, laterStroke]
                ),
                elements: [firstElement, deletedElement, laterElement],
                pages: pages,
                geometry: geometry
            )

            XCTAssertEqual(result.drawing.strokes.count, 2)
            XCTAssertEqual(result.drawing.strokes[0].transform, firstStroke.transform)
            XCTAssertEqual(
                result.drawing.strokes[1].transform,
                laterStroke.transform.concatenating(
                    CGAffineTransform(
                        translationX: 0,
                        y: -geometry.pageHeight
                    )
                )
            )
            XCTAssertEqual(result.elements.map(\.id), [firstElement.id, laterElement.id])
            XCTAssertEqual(result.elements[0], firstElement)
            XCTAssertEqual(
                result.elements[1].frame.y,
                laterElement.frame.y - Double(geometry.pageHeight),
                accuracy: 0.001
            )
            XCTAssertEqual(result.pages.map(\.id), [pages[0].id, pages[2].id])
            XCTAssertEqual(result.pages.map(\.order), [0, 1])
        }
    }

    func testBoundaryStraddlingStrokesFollowTheirMidpointBands() throws {
        let geometry = PageGeometry.a4
        let deletedStroke = CanvasFixtures.makeStroke(
            locations: [
                CGPoint(x: 20, y: geometry.pageHeight - 80),
                CGPoint(x: 60, y: geometry.pageHeight + 120),
            ],
            size: CGSize(width: 16, height: 16)
        )
        let laterStroke = CanvasFixtures.makeStroke(
            locations: [
                CGPoint(x: 20, y: 2 * geometry.pageHeight - 120),
                CGPoint(x: 60, y: 2 * geometry.pageHeight + 160),
            ],
            size: CGSize(width: 16, height: 16)
        )
        XCTAssertLessThan(deletedStroke.renderBounds.minY, geometry.pageHeight)
        XCTAssertGreaterThan(deletedStroke.renderBounds.midY, geometry.pageHeight)
        XCTAssertLessThan(laterStroke.renderBounds.minY, 2 * geometry.pageHeight)
        XCTAssertGreaterThan(laterStroke.renderBounds.midY, 2 * geometry.pageHeight)

        let result = PageDeleter.deletePage(
            at: 1,
            drawing: PKDrawing(strokes: [deletedStroke, laterStroke]),
            elements: [],
            pages: makePages(count: 3),
            geometry: geometry
        )

        let moved = try XCTUnwrap(result.drawing.strokes.first)
        XCTAssertEqual(result.drawing.strokes.count, 1)
        XCTAssertEqual(
            moved.transform,
            laterStroke.transform.concatenating(
                CGAffineTransform(
                    translationX: 0,
                    y: -geometry.pageHeight
                )
            )
        )
    }

    func testDeletingFirstPageHandsAttachmentToNewFirstPageAndResequencesOrders() {
        let attachmentElement = CanvasFixtures.makeImageElement(
            frame: CanvasRect(x: 20, y: 30, width: 40, height: 50)
        )
        let survivorElement = CanvasFixtures.makeImageElement(
            frame: CanvasRect(
                x: 25,
                y: Double(PageGeometry.a4.pageHeight + 45),
                width: 30,
                height: 35
            )
        )
        let pages = [
            makePage(
                id: UUID(),
                order: 0,
                path: "pages/attachment/drawing.data",
                text: "attachment",
                background: .ruled,
                elements: [attachmentElement, survivorElement]
            ),
            makePage(
                id: UUID(),
                order: 1,
                path: "pages/second/drawing.data",
                text: "second",
                background: .grid
            ),
            makePage(
                id: UUID(),
                order: 2,
                path: "pages/third/drawing.data",
                text: "third",
                background: .blank
            ),
        ]

        let result = PageDeleter.deletePage(
            at: 0,
            drawing: PKDrawing(),
            elements: [attachmentElement, survivorElement],
            pages: pages,
            geometry: .a4
        )

        var expectedSurvivor = survivorElement
        expectedSurvivor.frame.y -= Double(PageGeometry.a4.pageHeight)
        XCTAssertFalse(result.elements.contains { $0.id == attachmentElement.id })
        XCTAssertEqual(result.elements, [expectedSurvivor])
        XCTAssertEqual(
            result.elements[0].frame.y,
            survivorElement.frame.y - Double(PageGeometry.a4.pageHeight),
            accuracy: 0.001
        )
        XCTAssertEqual(result.pages.map(\.id), [pages[1].id, pages[2].id])
        XCTAssertEqual(result.pages.map(\.order), [0, 1])
        XCTAssertEqual(result.pages[0].drawingAssetPath, pages[0].drawingAssetPath)
        XCTAssertEqual(result.pages[0].plainText, pages[0].plainText)
        XCTAssertEqual(result.pages[0].elements, result.elements)
        XCTAssertEqual(result.pages[0].background, pages[1].background)
    }

    func testDeletingPDFPageDropsItsReferenceAndPreservesOtherReferences() {
        let firstReference = PDFPageReference(
            assetPath: "assets/first.pdf",
            pageIndex: 2
        )
        let deletedReference = PDFPageReference(
            assetPath: "assets/deleted.pdf",
            pageIndex: 4
        )
        let thirdReference = PDFPageReference(
            assetPath: "assets/third.pdf",
            pageIndex: 6
        )
        let pages = [
            makePage(
                id: UUID(),
                order: 0,
                path: "pages/first/drawing.data",
                text: "first",
                background: .pdf,
                pdfPage: firstReference
            ),
            makePage(
                id: UUID(),
                order: 1,
                path: "pages/deleted/drawing.data",
                text: "deleted",
                background: .pdf,
                pdfPage: deletedReference
            ),
            makePage(
                id: UUID(),
                order: 2,
                path: "pages/third/drawing.data",
                text: "third",
                background: .pdf,
                pdfPage: thirdReference
            ),
        ]

        let result = PageDeleter.deletePage(
            at: 1,
            drawing: PKDrawing(),
            elements: [],
            pages: pages,
            geometry: .a4
        )

        XCTAssertEqual(result.pages.map(\.id), [pages[0].id, pages[2].id])
        XCTAssertFalse(result.pages.contains { $0.pdfPage == deletedReference })
        XCTAssertEqual(result.pages[0].pdfPage, firstReference)
        XCTAssertEqual(result.pages[1].pdfPage, thirdReference)
    }

    func testInvalidDeletesPreserveEveryInputValue() {
        let stroke = CanvasFixtures.makeStroke(
            locations: [
                CGPoint(x: 10, y: PageGeometry.a4.pageHeight + 20),
                CGPoint(x: 30, y: PageGeometry.a4.pageHeight + 40),
            ]
        )
        let element = CanvasFixtures.makeImageElement(
            frame: CanvasRect(x: 10, y: 30, width: 40, height: 50)
        )
        let drawing = PKDrawing(strokes: [stroke])

        let singlePage = makePages(count: 1)
        let lastPageResult = PageDeleter.deletePage(
            at: 0,
            drawing: drawing,
            elements: [element],
            pages: singlePage,
            geometry: .a4
        )
        XCTAssertEqual(
            lastPageResult.drawing.dataRepresentation(),
            drawing.dataRepresentation()
        )
        XCTAssertEqual(lastPageResult.elements, [element])
        assertPages(lastPageResult.pages, equal: singlePage)

        let multiplePages = makePages(count: 3)
        let outOfRangeResult = PageDeleter.deletePage(
            at: multiplePages.count,
            drawing: drawing,
            elements: [element],
            pages: multiplePages,
            geometry: .a4
        )
        XCTAssertEqual(
            outOfRangeResult.drawing.dataRepresentation(),
            drawing.dataRepresentation()
        )
        XCTAssertEqual(outOfRangeResult.elements, [element])
        assertPages(outOfRangeResult.pages, equal: multiplePages)
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
        pdfPage: PDFPageReference? = nil,
        elements: [CanvasElement] = []
    ) -> NotePage {
        NotePage(
            id: id,
            order: order,
            plainText: text,
            drawingAssetPath: path,
            background: background,
            pdfPage: pdfPage,
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
