import Foundation
import Testing
@testable import VellumCore

@Test("Lines within a page are assembled from top to bottom")
func pageTextAssemblerOrdersLinesTopToBottom() {
    let pages = [recognitionPage()]
    let lines = [
        recognizedLine("Bottom", x: 10, y: 200),
        recognizedLine("Top", x: 10, y: 20),
        recognizedLine("Middle", x: 10, y: 100),
    ]

    let result = PageTextAssembler.assemble(
        inkLines: lines,
        pages: pages,
        geometry: .a4
    )

    #expect(result[0].lines.map(\.text) == ["Top", "Middle", "Bottom"])
    #expect(result[0].plainText == "Top\nMiddle\nBottom")
}

@Test("Lines at the same height are ordered from left to right")
func pageTextAssemblerUsesHorizontalTiebreak() {
    let lines = [
        recognizedLine("Right", x: 200, y: 50),
        recognizedLine("Left", x: 20, y: 50),
    ]

    let result = PageTextAssembler.assemble(
        inkLines: lines,
        pages: [recognitionPage()],
        geometry: .a4
    )

    #expect(result[0].lines.map(\.text) == ["Left", "Right"])
}

@Test("Ink and typed lines are interleaved by position")
func pageTextAssemblerInterleavesSources() {
    let typed = textElement("Typed middle", x: 10, y: 100)
    let pages = [recognitionPage(elements: [typed])]
    let inkLines = [
        recognizedLine("Ink bottom", x: 10, y: 200),
        recognizedLine("Ink top", x: 10, y: 20),
    ]

    let result = PageTextAssembler.assemble(
        inkLines: inkLines,
        pages: pages,
        geometry: .a4
    )

    #expect(result[0].lines.map(\.text) == ["Ink top", "Typed middle", "Ink bottom"])
    #expect(result[0].lines.map(\.source) == [.ink, .typed, .ink])
}

@Test("Empty and whitespace-only typed boxes are omitted")
func pageTextAssemblerSkipsBlankTypedText() {
    let pages = [
        recognitionPage(elements: [
            textElement("", x: 10, y: 10),
            textElement("  \n\t ", x: 10, y: 30),
        ])
    ]

    let result = PageTextAssembler.assemble(
        inkLines: [],
        pages: pages,
        geometry: .a4
    )

    #expect(result[0].lines.isEmpty)
    #expect(result[0].plainText.isEmpty)
}

@Test("Lines are assigned to the page band containing their midpoint")
func pageTextAssemblerAssignsMultipleBands() {
    let geometry = PageGeometry.a4
    let pageHeight = Double(geometry.pageHeight)
    let pages = [recognitionPage(order: 0), recognitionPage(order: 1)]
    let lines = [
        recognizedLine("First page", x: 10, y: 20),
        recognizedLine("Second page", x: 10, y: pageHeight + 20),
    ]

    let result = PageTextAssembler.assemble(
        inkLines: lines,
        pages: pages,
        geometry: geometry
    )

    #expect(result.count == 2)
    #expect(result[0].pageID == pages[0].id)
    #expect(result[0].pageIndex == 0)
    #expect(result[0].plainText == "First page")
    #expect(result[1].pageID == pages[1].id)
    #expect(result[1].pageIndex == 1)
    #expect(result[1].plainText == "Second page")
}

@Test("A line beyond the page range is clamped into the final band")
func pageTextAssemblerClampsOutOfRangeLines() {
    let geometry = PageGeometry.a4
    let pages = [recognitionPage(order: 0), recognitionPage(order: 1)]
    let line = recognizedLine(
        "Far below",
        x: 10,
        y: Double(geometry.pageHeight) * 20
    )

    let result = PageTextAssembler.assemble(
        inkLines: [line],
        pages: pages,
        geometry: geometry
    )

    #expect(result[0].lines.isEmpty)
    #expect(result[1].lines == [line])
}

@Test("No pages produces no recognized page output")
func pageTextAssemblerHandlesNoPages() {
    let result = PageTextAssembler.assemble(
        inkLines: [recognizedLine("Unused", x: 0, y: 0)],
        pages: [],
        geometry: .a4
    )

    #expect(result.isEmpty)
}

@Test("Every page is represented when there are no lines")
func pageTextAssemblerProducesEmptyPageBands() {
    let pages = [recognitionPage(order: 0), recognitionPage(order: 1)]

    let result = PageTextAssembler.assemble(
        inkLines: [],
        pages: pages,
        geometry: .a4
    )

    #expect(result.count == pages.count)
    #expect(result.allSatisfy { $0.lines.isEmpty })
    #expect(result.allSatisfy { $0.plainText.isEmpty })
}

private func recognitionPage(
    id: UUID = UUID(),
    order: Int = 0,
    plainText: String = "",
    elements: [CanvasElement] = []
) -> NotePage {
    NotePage(
        id: id,
        order: order,
        plainText: plainText,
        drawingAssetPath: "drawing.data",
        background: .blank,
        elements: elements
    )
}

private func recognizedLine(
    _ text: String,
    x: Double,
    y: Double,
    width: Double = 100,
    height: Double = 20
) -> RecognizedLine {
    RecognizedLine(
        text: text,
        rect: CanvasRect(x: x, y: y, width: width, height: height),
        confidence: 0.9,
        source: .ink
    )
}

private func textElement(_ text: String, x: Double, y: Double) -> CanvasElement {
    CanvasElement(
        content: .text(
            TextBoxContent(
                text: text,
                fontSize: 16,
                color: CodableColor(red: 0, green: 0, blue: 0)
            )
        ),
        frame: CanvasRect(x: x, y: y, width: 100, height: 20)
    )
}
