import Foundation
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class ToolPreferencesTests: XCTestCase {
    func testFullCodableRoundTripPreservesFavoritesOrder() throws {
        var original = ToolPreferences.default
        original.schemaVersion = 7
        original.pen = InkToolConfig(
            style: .fountainPen,
            color: CodableColor(hex: "#112233", alpha: 0.8),
            width: 6
        )
        original.pencil = InkToolConfig(
            style: .crayon,
            color: CodableColor(hex: "#445566"),
            width: 9
        )
        original.highlighter = InkToolConfig(
            style: .watercolor,
            color: CodableColor(hex: "#778899", alpha: 0.6),
            width: 18
        )
        original.eraser = EraserConfig(mode: .wholeStroke, width: 30)
        original.selection = SelectionConfig(mode: .boxed)
        original.text = TextConfig(fontSize: 22, color: CodableColor(hex: "#AABBCC"))
        original.favorites = [
            CodableColor(hex: "#D07B3A"),
            CodableColor(hex: "#4E6E58"),
            CodableColor(hex: "#26221B"),
        ]
        original.lastSelectedTool = .pencil
        original.isToolbarCollapsed = true

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToolPreferences.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.favorites, original.favorites)
    }

    func testEmptyObjectDecodesAsDefault() throws {
        let decoded = try JSONDecoder().decode(
            ToolPreferences.self,
            from: Data("{}".utf8)
        )

        XCTAssertEqual(decoded, .default)
    }

    func testUnknownToolAndInkStyleRawValuesFallBackWithoutThrowing() throws {
        let json = """
        {
          "lastSelectedTool": "futureTool",
          "pen": { "style": "futurePen" },
          "pencil": { "style": "futurePencil" },
          "highlighter": { "style": "futureHighlighter" }
        }
        """

        let decoded = try JSONDecoder().decode(
            ToolPreferences.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.lastSelectedTool, .pen)
        XCTAssertEqual(decoded.pen.style, .pen)
        XCTAssertEqual(decoded.pencil.style, .pencil)
        XCTAssertEqual(decoded.highlighter.style, .marker)
    }

    func testMissingToolbarDockDecodesAsDefault() throws {
        let json = """
        {
          "schemaVersion": 1
        }
        """

        let decoded = try JSONDecoder().decode(
            ToolPreferences.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.toolbarDock, ToolPreferences.default.toolbarDock)
    }

    func testUnknownToolbarDockEdgeFallsBackToDefaultAndPreservesFraction() throws {
        let json = """
        {
          "toolbarDock": { "edge": "diagonal", "fraction": 0.25 }
        }
        """

        let decoded = try JSONDecoder().decode(
            ToolPreferences.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.toolbarDock.edge, ToolPreferences.default.toolbarDock.edge)
        XCTAssertEqual(decoded.toolbarDock.fraction, 0.25)
    }

    func testToolbarDockFractionIsClampedToUnitRange() throws {
        let tooHighJSON = """
        {
          "toolbarDock": { "edge": "top", "fraction": 1.7 }
        }
        """
        let tooLowJSON = """
        {
          "toolbarDock": { "edge": "left", "fraction": -0.3 }
        }
        """

        let tooHighDecoded = try JSONDecoder().decode(
            ToolPreferences.self,
            from: Data(tooHighJSON.utf8)
        )
        let tooLowDecoded = try JSONDecoder().decode(
            ToolPreferences.self,
            from: Data(tooLowJSON.utf8)
        )

        XCTAssertEqual(tooHighDecoded.toolbarDock.fraction, 1.0)
        XCTAssertEqual(tooLowDecoded.toolbarDock.fraction, 0.0)
    }

    func testToolbarDockCodableRoundTripPreservesPlacement() throws {
        var original = ToolPreferences.default
        original.toolbarDock = ToolbarDockPlacement(edge: .right, fraction: 0.25)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToolPreferences.self, from: data)

        XCTAssertEqual(decoded.toolbarDock, original.toolbarDock)
    }

    func testStoreRoundTripPersistsValuesAndCollapsedState() throws {
        let suiteName = "ToolPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = ToolPreferencesStore(defaults: defaults)
        firstStore.setColor(CodableColor(hex: "#123456"), for: .pen)
        firstStore.setWidth(8, for: .pencil)
        firstStore.setStyle(.watercolor, for: .highlighter)
        firstStore.update { preferences in
            preferences.lastSelectedTool = .eraser
            preferences.isToolbarCollapsed = true
        }
        firstStore.flush()

        let secondStore = ToolPreferencesStore(defaults: defaults)

        XCTAssertEqual(secondStore.preferences.pen.color, CodableColor(hex: "#123456"))
        XCTAssertEqual(secondStore.preferences.pencil.width, 8)
        XCTAssertEqual(secondStore.preferences.highlighter.style, .watercolor)
        XCTAssertEqual(secondStore.preferences.lastSelectedTool, .eraser)
        XCTAssertTrue(secondStore.preferences.isToolbarCollapsed)
    }

    func testAddFavoriteDeduplicatesExistingColor() {
        let suiteName = "ToolPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ToolPreferencesStore(defaults: defaults)
        let original = store.preferences.favorites

        store.addFavorite(original[0])

        XCTAssertEqual(store.preferences.favorites, original)
        store.flush()
    }

    func testRemoveMoveAndResetFavoritesProduceExpectedOrder() {
        let suiteName = "ToolPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ToolPreferencesStore(defaults: defaults)
        let first = CodableColor(hex: "#111111")
        let second = CodableColor(hex: "#222222")
        let third = CodableColor(hex: "#333333")
        let fourth = CodableColor(hex: "#444444")
        store.update { preferences in
            preferences.favorites = [first, second, third, fourth]
        }

        store.removeFavorite(at: IndexSet(integer: 1))
        XCTAssertEqual(store.preferences.favorites, [first, third, fourth])

        store.moveFavorites(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.preferences.favorites, [fourth, first, third])

        store.resetFavorites()
        XCTAssertEqual(store.preferences.favorites, ToolPreferences.defaultFavorites)
        store.flush()
    }
}
