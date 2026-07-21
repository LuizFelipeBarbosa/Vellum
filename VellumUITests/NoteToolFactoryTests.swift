import CoreGraphics
import PencilKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class NoteToolFactoryTests: XCTestCase {
    func testEachToolIDMapsToExpectedPKToolType() throws {
        let preferences = ToolPreferences.default

        XCTAssertTrue(NoteToolFactory.tool(for: .pen, preferences: preferences) is PKInkingTool)
        XCTAssertTrue(NoteToolFactory.tool(for: .pencil, preferences: preferences) is PKInkingTool)
        XCTAssertTrue(
            NoteToolFactory.tool(for: .highlighter, preferences: preferences) is PKInkingTool
        )
        XCTAssertTrue(NoteToolFactory.tool(for: .eraser, preferences: preferences) is PKEraserTool)
        XCTAssertNil(NoteToolFactory.tool(for: .select, preferences: preferences))
        XCTAssertNil(NoteToolFactory.tool(for: .text, preferences: preferences))
    }

    func testEraserModesMapToExpectedTypes() throws {
        var preferences = ToolPreferences.default
        preferences.eraser = EraserConfig(mode: .partial, width: 19)
        let partial = try XCTUnwrap(
            NoteToolFactory.tool(for: .eraser, preferences: preferences) as? PKEraserTool
        )

        preferences.eraser.mode = .wholeStroke
        let wholeStroke = try XCTUnwrap(
            NoteToolFactory.tool(for: .eraser, preferences: preferences) as? PKEraserTool
        )

        // PencilKit reports a width-specified bitmap eraser as .fixedWidthBitmap.
        XCTAssertEqual(partial.eraserType, .fixedWidthBitmap)
        XCTAssertEqual(partial.width, 19)
        XCTAssertEqual(wholeStroke.eraserType, .vector)
    }

    func testFountainPenMapsTypeWidthAndSRGBComponents() throws {
        let color = CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let tool = NoteToolFactory.inkingTool(
            InkToolConfig(style: .fountainPen, color: color, width: 6)
        )
        let components = try rgbaComponents(of: tool.color.cgColor)

        XCTAssertEqual(tool.inkType, .fountainPen)
        XCTAssertEqual(tool.width, 6)
        XCTAssertEqual(components.red, 0.2, accuracy: 0.001)
        XCTAssertEqual(components.green, 0.4, accuracy: 0.001)
        XCTAssertEqual(components.blue, 0.6, accuracy: 0.001)
        XCTAssertEqual(components.alpha, 0.8, accuracy: 0.001)
    }

    func testHugeWidthClampsToEachInkToolsMaximum() throws {
        let cases: [(ToolID, InkStyle)] = [
            (.pen, .pen),
            (.pencil, .pencil),
            (.highlighter, .marker),
        ]

        for (toolID, style) in cases {
            var preferences = ToolPreferences.default
            let keyPath = try XCTUnwrap(toolID.inkConfigKeyPath)
            preferences[keyPath: keyPath] = InkToolConfig(
                style: style,
                color: CodableColor(hex: "#26221B"),
                width: 999
            )
            let tool = try XCTUnwrap(
                NoteToolFactory.tool(for: toolID, preferences: preferences) as? PKInkingTool
            )
            let expectedMaximum = min(
                NoteToolFactory.widthRange(for: style).upperBound,
                Double(tool.inkType.validWidthRange.upperBound)
            )

            XCTAssertEqual(Double(tool.width), expectedMaximum, accuracy: 0.001)
        }
    }

    func testMarkerUsesFixedAlphaAndPenPreservesStoredAlpha() throws {
        let opaqueColor = CodableColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 1)
        let marker = NoteToolFactory.inkingTool(
            InkToolConfig(style: .marker, color: opaqueColor, width: 12)
        )
        let pen = NoteToolFactory.inkingTool(
            InkToolConfig(style: .pen, color: opaqueColor, width: 4)
        )

        XCTAssertEqual(try rgbaComponents(of: marker.color.cgColor).alpha, 0.55, accuracy: 0.001)
        XCTAssertEqual(try rgbaComponents(of: pen.color.cgColor).alpha, 1, accuracy: 0.001)
    }

    func testDefaultFavoritesContainsTwelveUniqueEntries() {
        XCTAssertEqual(ToolPreferences.defaultFavorites.count, 12)
        XCTAssertEqual(Set(ToolPreferences.defaultFavorites).count, 12)
    }

    func testValidStylesReturnsDocumentedLists() {
        XCTAssertEqual(NoteToolFactory.validStyles(for: .pen), [.pen, .fountainPen, .monoline])
        XCTAssertEqual(NoteToolFactory.validStyles(for: .pencil), [.pencil, .crayon])
        XCTAssertEqual(NoteToolFactory.validStyles(for: .highlighter), [.marker, .watercolor])
        XCTAssertEqual(NoteToolFactory.validStyles(for: .eraser), [])
        XCTAssertEqual(NoteToolFactory.validStyles(for: .select), [])
        XCTAssertEqual(NoteToolFactory.validStyles(for: .text), [])
    }

    private func rgbaComponents(
        of color: CGColor
    ) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let converted = try XCTUnwrap(
            color.converted(to: colorSpace, intent: .defaultIntent, options: nil)
        )
        let components = try XCTUnwrap(converted.components)
        XCTAssertEqual(components.count, 4)
        return (components[0], components[1], components[2], components[3])
    }
}
