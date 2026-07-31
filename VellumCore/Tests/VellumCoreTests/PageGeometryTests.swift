import CoreGraphics
import Foundation
import Testing
@testable import VellumCore

private let letterAspect = 792.0 / 612.0

@Test("Page geometry clamps aspect ratios to its supported range")
func pageGeometryClampsAspectRatios() {
    #expect(PageGeometry(portraitAspectRatio: 0.01).portraitAspectRatio == 0.5)
    #expect(PageGeometry(portraitAspectRatio: 10).portraitAspectRatio == 3)
}

@Test("Landscape geometry swaps the upright page axes")
func landscapeGeometrySwapsUprightAxes() {
    let portrait = PageGeometry.a4
    let landscape = PageGeometry.a4Landscape

    #expect(landscape.contentWidth == portrait.pageHeight)
    #expect(landscape.pageHeight == portrait.contentWidth)
    #expect(landscape.orientation == .landscape)
    #expect(landscape.aspectRatio == 1 / portrait.aspectRatio)
}

@Test("Landscape page rectangles use the swapped dimensions")
func landscapePageRectUsesSwappedDimensions() {
    let geometry = PageGeometry.a4Landscape

    #expect(geometry.pageRect(index: 2) == CGRect(
        x: 0,
        y: 2 * geometry.pageHeight,
        width: geometry.contentWidth,
        height: geometry.pageHeight
    ))
}

@Test("Landscape A4 exports with swapped PDF dimensions")
func landscapeA4PDFSizeUsesSwappedDimensions() {
    #expect(PageGeometry.a4Landscape.pdfPageSize == CGSize(width: 841.8, height: 595.2))
}

@Test("Portrait aspect ratio round trips through landscape geometry")
func portraitAspectRatioRoundTripsThroughLandscapeGeometry() {
    let uprightAspectRatio = PageGeometry.aspectRatioRange.upperBound
    let landscape = PageGeometry(
        portraitAspectRatio: uprightAspectRatio,
        orientation: .landscape
    )
    let roundTripped = PageGeometry(
        portraitAspectRatio: landscape.portraitAspectRatio,
        orientation: .portrait
    )

    #expect(landscape.portraitAspectRatio == uprightAspectRatio)
    #expect(roundTripped.portraitAspectRatio == uprightAspectRatio)
}

@Test("Letter geometry stacks and indexes pages with the letter page height")
func letterGeometryUsesLetterPageHeight() {
    let geometry = PageGeometry(portraitAspectRatio: letterAspect)
    let expectedHeight = PageLayout.portraitContentWidth * CGFloat(letterAspect)
    let pageRect = geometry.pageRect(index: 2)

    #expect(geometry.pageHeight == expectedHeight)
    #expect(pageRect == CGRect(
        x: 0,
        y: 2 * expectedHeight,
        width: PageLayout.portraitContentWidth,
        height: expectedHeight
    ))
    #expect(geometry.contentHeight(pageCount: 3) == 3 * expectedHeight)
    #expect(geometry.pageIndex(forContentY: 1.5 * expectedHeight, pageCount: 3) == 1)
    #expect(geometry.pageIndex(forContentY: 4 * expectedHeight, pageCount: 3) == 2)
}

@Test("Export page sizes scale with the geometry aspect ratio")
func exportPageSizesScaleWithAspectRatio() {
    let geometry = PageGeometry(portraitAspectRatio: letterAspect)

    #expect(geometry.pdfPageSize.width == 595.2)
    #expect(geometry.pdfPageSize.height == 595.2 * CGFloat(letterAspect))
    #expect(geometry.rasterPageSizePixels.width == 1_536)
    #expect(
        geometry.rasterPageSizePixels.height
            == (1_536 * CGFloat(letterAspect)).rounded()
    )
}

@Test("A4 geometry preserves the former fixed export dimensions")
func a4GeometryPreservesFormerFixedDimensions() {
    #expect(PageGeometry.a4.pageHeight == 768 * CGFloat(841.8 / 595.2))
    #expect(PageGeometry.a4.pdfPageSize == CGSize(width: 595.2, height: 841.8))
    #expect(PageGeometry.a4.rasterPageSizePixels == CGSize(width: 1_536, height: 2_172))
}

@Test("A letter PDF page fills a letter geometry band")
func letterPDFPageFillsLetterBand() {
    let geometry = PageGeometry(portraitAspectRatio: letterAspect)
    let pageRect = geometry.pageRect(index: 1)
    let fittedRect = geometry.fittedRect(
        forSourcePageSize: CGSize(width: 612, height: 792),
        pageIndex: 1
    )

    #expect(abs(fittedRect.minX - pageRect.minX) <= 0.5)
    #expect(abs(fittedRect.minY - pageRect.minY) <= 0.5)
    #expect(abs(fittedRect.width - pageRect.width) <= 0.5)
    #expect(abs(fittedRect.height - pageRect.height) <= 0.5)
}

@Test("A note page aspect ratio round trips through persistence")
func notePageAspectRatioRoundTrip() throws {
    let note = geometryTestNote(pageAspectRatio: letterAspect)
    let decoded = try FilePersistence.decoder().decode(
        Note.self,
        from: FilePersistence.encoder().encode(note)
    )

    #expect(decoded.pageAspectRatio == note.pageAspectRatio)
    #expect(decoded.pageGeometry == PageGeometry(portraitAspectRatio: letterAspect))
}

@Test("A manifest without page aspect ratio defaults to A4")
func manifestWithoutPageAspectRatioDefaultsToA4() throws {
    let encoded = try FilePersistence.encoder().encode(geometryTestNote())
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "pageAspectRatio")
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try FilePersistence.decoder().decode(Note.self, from: data)

    #expect(decoded.pageAspectRatio == PageLayout.a4AspectRatio)
    #expect(decoded.pageGeometry == .a4)
}

@Test("Out-of-range manifest page aspect ratios clamp on decode", arguments: [
    (0.01, PageGeometry.aspectRatioRange.lowerBound),
    (10.0, PageGeometry.aspectRatioRange.upperBound),
])
func manifestPageAspectRatioClamps(value: Double, expected: Double) throws {
    let encoded = try FilePersistence.encoder().encode(geometryTestNote())
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["pageAspectRatio"] = value
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try FilePersistence.decoder().decode(Note.self, from: data)

    #expect(decoded.pageAspectRatio == expected)
}

private func geometryTestNote(
    pageAspectRatio: Double = PageLayout.a4AspectRatio
) -> Note {
    let pageID = UUID()
    return Note(
        id: UUID(),
        schemaVersion: Note.currentSchemaVersion,
        revision: 1,
        title: "Geometry",
        tags: [],
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        pages: [
            NotePage(
                id: pageID,
                order: 0,
                plainText: "",
                drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
                background: .blank
            )
        ],
        pageAspectRatio: pageAspectRatio
    )
}
