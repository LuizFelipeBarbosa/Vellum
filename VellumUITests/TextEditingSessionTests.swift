import Foundation
@testable import Vellum
import VellumCore
import XCTest

@MainActor
final class TextEditingSessionTests: XCTestCase {
    func testAddElementOnEmptyStoreMaterializesKindDefaultPlacement() throws {
        let elements = [
            makeTextElement(text: "Text"),
            makeImageElement(assetPath: "assets/image.jpg"),
            makeShapeElement(),
            makeUnknownElement(),
        ]

        for element in elements {
            let store = CanvasElementsStore()

            store.addElement(element)

            let stored = try XCTUnwrap(store.elements.first)
            XCTAssertEqual(stored.id, element.id)
            XCTAssertEqual(stored.layerPlacement, element.effectivePlacement)
        }
    }

    func testAddsPreserveMaterializedOrderAndOnlyStampAppendedElements() {
        let existingImage = makeImageElement(
            assetPath: "assets/existing.jpg",
            layerPlacement: .aboveInk
        )
        let existingText = makeTextElement(
            text: "Existing",
            layerPlacement: .belowInk
        )
        let store = CanvasElementsStore()
        store.hydrate([existingImage, existingText])

        let appendedShape = makeShapeElement()
        store.addElement(appendedShape)
        let appendedText = makeTextElement(text: "Appended")
        store.addElementLive(appendedText)

        XCTAssertEqual(
            store.elements.map(\.id),
            [existingImage.id, existingText.id, appendedShape.id, appendedText.id]
        )
        XCTAssertEqual(
            store.elements.map(\.layerPlacement),
            [.aboveInk, .belowInk, .belowInk, .aboveInk]
        )
    }

    func testAddsKeepPerBandScreenOrderAlignedWithEffectiveZOrder() {
        let store = CanvasElementsStore()
        store.addElement(makeTextElement(text: "First text"))
        store.addElementLive(makeImageElement(assetPath: "assets/first.jpg"))
        store.addElement(makeShapeElement())
        store.addElementLive(makeTextElement(text: "Second text"))
        store.addElement(makeImageElement(assetPath: "assets/second.jpg"))

        XCTAssertTrue(store.elements.allSatisfy { $0.layerPlacement != nil })
        let effectiveOrder = store.elements.sortedByEffectiveZ()
        for placement in [LayerPlacement.belowInk, .aboveInk] {
            XCTAssertEqual(
                store.elements
                    .filter { $0.effectivePlacement == placement }
                    .map(\.id),
                effectiveOrder
                    .filter { $0.effectivePlacement == placement }
                    .map(\.id)
            )
        }
    }

    func testHydrateMaterializesLegacyElementsInHistoricalBandOrder() {
        let firstText = makeTextElement(text: "First")
        let unknown = makeUnknownElement()
        let firstImage = makeImageElement(assetPath: "assets/first.jpg")
        let shape = makeShapeElement()
        let secondImage = makeImageElement(assetPath: "assets/second.jpg")
        let secondText = makeTextElement(text: "Second")
        let legacyElements = [
            firstText,
            unknown,
            firstImage,
            shape,
            secondImage,
            secondText,
        ]
        XCTAssertTrue(legacyElements.allSatisfy { $0.layerPlacement == nil })

        let store = CanvasElementsStore()
        store.hydrate(legacyElements)

        XCTAssertEqual(
            store.elements.map(\.id),
            [
                firstImage.id,
                secondImage.id,
                unknown.id,
                shape.id,
                firstText.id,
                secondText.id,
            ]
        )
        XCTAssertEqual(
            store.elements.map(\.layerPlacement),
            [.belowInk, .belowInk, .belowInk, .belowInk, .aboveInk, .aboveInk]
        )
    }

    func testWhitespaceOnlySessionRemovesElementWithOneUndoStep() {
        let (store, undoManager) = makeStore()
        let element = makeTextElement(text: "Before")
        store.hydrate([element])
        let baseline = store.elements

        store.beginTextEditingSession(for: element.id)
        store.updateElementLive(
            replacingText(in: baseline[0], with: " \n ")
        )
        store.finishTextEditingSession(matching: element.id)

        XCTAssertTrue(store.elements.isEmpty)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Remove Text Box")

        undoManager.undo()

        XCTAssertEqual(store.elements, baseline)
        XCTAssertFalse(
            undoManager.canUndo,
            "The session must register exactly one undo step"
        )
    }

    func testToolChangeFinishTrimsTextAndIsIdempotent() throws {
        let (store, undoManager) = makeStore()
        let element = makeTextElement(
            text: "Before",
            layerPlacement: .belowInk
        )
        store.hydrate([element])
        let baseline = store.elements
        var changeCount = 0
        store.onElementsChanged = { _ in changeCount += 1 }

        store.beginTextEditingSession(for: element.id)
        store.updateElementLive(
            replacingText(in: baseline[0], with: "  hello  ")
        )
        store.finishTextEditingSession(matching: nil)

        let finalizedElements = store.elements
        let finalized = try XCTUnwrap(finalizedElements.first)
        guard case .text(let content) = finalized.content else {
            return XCTFail("Expected a text element")
        }
        XCTAssertEqual(content.text, "hello")
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Edit Text")

        let changeCountAfterFinalize = changeCount
        store.finishTextEditingSession(matching: nil)

        XCTAssertEqual(store.elements, finalizedElements)
        XCTAssertEqual(undoManager.undoActionName, "Edit Text")
        XCTAssertEqual(changeCount, changeCountAfterFinalize)
        undoManager.undo()
        XCTAssertEqual(store.elements, baseline)
        XCTAssertFalse(
            undoManager.canUndo,
            "The session must register exactly one undo step"
        )
    }

    func testBeginningDifferentSessionFinalizesActiveSessionFirst() {
        let (store, undoManager) = makeStore()
        let first = makeTextElement(text: "First")
        let second = makeTextElement(text: "Second")
        store.hydrate([first, second])

        store.beginTextEditingSession(for: first.id)
        store.updateElementLive(
            replacingText(in: store.elements[0], with: " \n ")
        )
        store.beginTextEditingSession(for: second.id)

        XCTAssertFalse(store.elements.contains { $0.id == first.id })
        XCTAssertTrue(store.elements.contains { $0.id == second.id })
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Remove Text Box")
    }

    func testFinishForWrongIDDoesNothingWithOrWithoutActiveSession() {
        let (store, undoManager) = makeStore()
        let activeElement = makeTextElement(text: "Active")
        let otherElement = makeTextElement(text: "Other")
        store.hydrate([activeElement, otherElement])
        let expectedElements = store.elements
        var changeCount = 0
        store.onElementsChanged = { _ in changeCount += 1 }

        store.beginTextEditingSession(for: activeElement.id)
        store.finishTextEditingSession(matching: otherElement.id)

        XCTAssertEqual(store.elements, expectedElements)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(changeCount, 0)

        let storeWithoutSession = CanvasElementsStore()
        storeWithoutSession.hydrate([otherElement])
        let expectedWithoutSession = storeWithoutSession.elements
        storeWithoutSession.finishTextEditingSession(matching: otherElement.id)

        XCTAssertEqual(storeWithoutSession.elements, expectedWithoutSession)
    }

    func testEmptyTextWithoutSessionUsesTransactionalRemovalFallback() {
        let (store, undoManager) = makeStore()
        let element = makeTextElement(text: " \n ")
        store.hydrate([element])

        store.finishTextEditingSession(matching: element.id)

        XCTAssertTrue(store.elements.isEmpty)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Remove Element")
    }

    func testNonEmptyTextWithoutSessionTrimsGrowsAndIsIdempotent() throws {
        let (store, undoManager) = makeStore()
        let element = makeTextElement(text: "  hello  ")
        store.hydrate([element])
        var changeCount = 0
        store.onElementsChanged = { _ in changeCount += 1 }

        store.finishTextEditingSession(matching: element.id)

        let finalizedElements = store.elements
        let finalized = try XCTUnwrap(finalizedElements.first)
        guard case .text(let content) = finalized.content else {
            return XCTFail("Expected a text element")
        }
        let expectedContent = TextBoxContent(
            text: "hello",
            fontSize: content.fontSize,
            color: content.color
        )
        let expectedHeight = max(
            44,
            NotePageRenderer.growTextFrame(
                element.frame,
                textContent: expectedContent
            ).height
        )
        XCTAssertEqual(content.text, "hello")
        XCTAssertEqual(finalized.frame.height, expectedHeight)
        XCTAssertGreaterThanOrEqual(finalized.frame.height, 44)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(changeCount, 1)

        store.finishTextEditingSession(matching: element.id)

        XCTAssertEqual(store.elements, finalizedElements)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(changeCount, 1)
    }

    private func makeStore() -> (CanvasElementsStore, UndoManager) {
        let store = CanvasElementsStore()
        let undoManager = UndoManager()
        store.undoManagerOverride = undoManager
        return (store, undoManager)
    }

    private func replacingText(
        in element: CanvasElement,
        with text: String
    ) -> CanvasElement {
        guard case .text(let content) = element.content else {
            XCTFail("Expected a text element")
            return element
        }
        var updated = element
        updated.content = .text(
            TextBoxContent(
                text: text,
                fontSize: content.fontSize,
                color: content.color
            )
        )
        return updated
    }

    private func makeTextElement(
        text: String,
        layerPlacement: LayerPlacement? = nil
    ) -> CanvasElement {
        CanvasElement(
            content: .text(
                TextBoxContent(
                    text: text,
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: CanvasRect(x: 10, y: 20, width: 160, height: 44),
            layerPlacement: layerPlacement
        )
    }

    private func makeImageElement(
        assetPath: String,
        layerPlacement: LayerPlacement? = nil
    ) -> CanvasElement {
        CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: assetPath,
                    originalPixelSize: CanvasSize(width: 200, height: 100)
                )
            ),
            frame: CanvasRect(x: 20, y: 30, width: 200, height: 100),
            layerPlacement: layerPlacement
        )
    }

    private func makeShapeElement(
        layerPlacement: LayerPlacement? = nil
    ) -> CanvasElement {
        CanvasElement(
            content: .shape(
                ShapeContent(
                    geometry: .ellipse,
                    strokeColor: CodableColor(red: 0, green: 0, blue: 0),
                    strokeWidth: 4
                )
            ),
            frame: CanvasRect(x: 30, y: 40, width: 120, height: 80),
            layerPlacement: layerPlacement
        )
    }

    private func makeUnknownElement() -> CanvasElement {
        CanvasElement(
            content: .unknown(
                UnknownContent(kind: "legacy-widget", payload: .null)
            ),
            frame: CanvasRect(x: 40, y: 50, width: 80, height: 60)
        )
    }
}
