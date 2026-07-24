import Foundation
@testable import Vellum
import VellumCore
import XCTest

private actor FailingActivityRepository: ActivityRepository {
    let noteID: UUID

    init(noteID: UUID) {
        self.noteID = noteID
    }

    func append(_ event: ActivityEvent) async throws {
        throw VellumError.noteNotFound(noteID)
    }

    func list(noteID: UUID?) async throws -> [ActivityEvent] {
        []
    }
}

@MainActor
final class ElementAutosaveRoundTripTests: XCTestCase {
    func testElementsRoundTripThroughAutosavePath() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let container = AppContainer.live(rootDirectory: rootDirectory)
        let note = try await container.notes.createNote(title: "Element round trip")
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()

        let textElement = CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Hello",
                    fontSize: 18,
                    color: CodableColor(red: 0.2, green: 0.4, blue: 0.6)
                )
            ),
            frame: CanvasRect(x: 10, y: 20, width: 100, height: 40)
        )
        let imageElement = CanvasElement(
            content: .image(
                ImageContent(
                    assetPath: "images/foo.png",
                    originalPixelSize: CanvasSize(width: 200, height: 200)
                )
            ),
            frame: CanvasRect(x: 50, y: 60, width: 200, height: 200)
        )

        model.canvasElements.addElement(textElement)
        model.canvasElements.addElement(imageElement)
        await model.flushPendingSave()

        let freshRepository = FileNoteRepository(rootDirectory: rootDirectory)
        let reloadedNote = try await freshRepository.loadNote(id: note.id)
        let reloadedElements = try XCTUnwrap(reloadedNote.pages.first?.elements)

        XCTAssertEqual(reloadedElements.count, 2)
        for (reloaded, original) in zip(reloadedElements, [textElement, imageElement]) {
            XCTAssertEqual(reloaded.id, original.id)
            XCTAssertEqual(reloaded.content, original.content)
            XCTAssertEqual(reloaded.frame, original.frame)
            XCTAssertEqual(reloaded.rotation, original.rotation)
            // The repository's ISO8601 encoding truncates dates to milliseconds.
            XCTAssertEqual(
                reloaded.createdAt.timeIntervalSinceReferenceDate,
                original.createdAt.timeIntervalSinceReferenceDate,
                accuracy: 0.001
            )
        }
    }

    func testHydrateDoesNotNotifyOrMarkModelEdited() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let container = AppContainer.live(rootDirectory: rootDirectory)
        let note = try await container.notes.createNote(title: "Silent hydration")
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()
        model.canvasElements.onElementsChanged = { _ in
            XCTFail("hydrate must not fire onElementsChanged")
        }

        let element = CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "Hydrated",
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: CanvasRect(x: 0, y: 0, width: 100, height: 40)
        )
        model.canvasElements.hydrate([element])

        XCTAssertEqual(model.canvasElements.elements, [element])
        XCTAssertEqual(model.saveState, .saved)
    }

    func testLiveTextUpdatesReachAutosaveWithoutCommit() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let container = AppContainer.live(rootDirectory: rootDirectory)
        let note = try await container.notes.createNote(title: "Live text autosave")
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()

        let element = CanvasElement(
            content: .text(
                TextBoxContent(
                    text: "",
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            ),
            frame: CanvasRect(x: 10, y: 20, width: 100, height: 40)
        )
        model.canvasElements.addElement(element)

        for typedText in ["H", "He", "Hello"] {
            var updated = element
            updated.content = .text(
                TextBoxContent(
                    text: typedText,
                    fontSize: 18,
                    color: CodableColor(red: 0, green: 0, blue: 0)
                )
            )
            model.canvasElements.updateElementLive(updated)
        }

        await model.flushPendingSave()

        let freshRepository = FileNoteRepository(rootDirectory: rootDirectory)
        let reloadedNote = try await freshRepository.loadNote(id: note.id)
        let reloadedElement = try XCTUnwrap(reloadedNote.pages.first?.elements.first)
        guard case .text(let reloadedText) = reloadedElement.content else {
            return XCTFail("Expected a text element")
        }
        XCTAssertEqual(reloadedText.text, "Hello")
    }

    func testDrawingCommitSurvivesPostManifestActivityFailure() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let notes = FileNoteRepository(rootDirectory: rootDirectory)
        let note = try await notes.createNote(title: "Post-manifest failure")
        let oldAssetPath = note.pages[0].drawingAssetPath
        let oldDrawingData = Data([0x01, 0x02, 0x03])
        let newDrawingData = Data([0x04, 0x05, 0x06])
        try await notes.saveAsset(
            oldDrawingData,
            noteID: note.id,
            relativePath: oldAssetPath
        )

        let proposals = FileProposalRepository(rootDirectory: rootDirectory)
        let activity = FailingActivityRepository(noteID: note.id)
        let agent = MockVellumAgent()
        let spaces = FileSpaceRepository(rootDirectory: rootDirectory)
        let entities = FileEntityRepository(rootDirectory: rootDirectory)
        let tasks = FileTaskRepository(rootDirectory: rootDirectory)
        let workspace = WorkspaceService(
            notes: notes,
            proposals: proposals,
            activity: activity,
            agent: agent,
            spaces: spaces,
            entities: entities,
            tasks: tasks
        )
        let graph = KnowledgeGraphService(notes: notes, spaces: spaces, entities: entities)
        let container = AppContainer(
            rootDirectory: rootDirectory,
            notes: notes,
            proposals: proposals,
            activity: activity,
            agent: agent,
            spaces: spaces,
            entities: entities,
            tasks: tasks,
            workspace: workspace,
            graph: graph,
            askService: AskService(
                notes: notes,
                answerer: MockAskAnswerer(),
                activity: activity
            )
        )
        let model = NoteScreenModel(
            noteID: note.id,
            container: container,
            onNoteChanged: { _ in }
        )
        await model.load()

        model.drawingChanged(newDrawingData)
        await model.flushPendingSave()

        XCTAssertEqual(model.saveState, .unsaved)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.note?.pages.first?.drawingAssetPath, oldAssetPath)

        let freshRepository = FileNoteRepository(rootDirectory: rootDirectory)
        let committedNote = try await freshRepository.loadNote(id: note.id)
        let committedAssetPath = try XCTUnwrap(committedNote.pages.first?.drawingAssetPath)
        let committedAssetData = try await freshRepository.loadAsset(
            noteID: note.id,
            relativePath: committedAssetPath
        )
        let oldAssetDataBeforePurge = try await freshRepository.loadAsset(
            noteID: note.id,
            relativePath: oldAssetPath
        )
        XCTAssertNotEqual(committedAssetPath, oldAssetPath)
        XCTAssertTrue(
            committedAssetPath.hasPrefix("pages/\(note.pages[0].id.uuidString)/drawing-")
        )
        XCTAssertTrue(committedAssetPath.hasSuffix(".data"))
        XCTAssertEqual(committedAssetData, newDrawingData)
        XCTAssertEqual(oldAssetDataBeforePurge, oldDrawingData)

        try await freshRepository.purgeUnreferencedAssets(noteID: note.id)

        let oldAssetDataAfterPurge = try await freshRepository.loadAsset(
            noteID: note.id,
            relativePath: oldAssetPath
        )
        let committedAssetDataAfterPurge = try await freshRepository.loadAsset(
            noteID: note.id,
            relativePath: committedAssetPath
        )
        XCTAssertNil(oldAssetDataAfterPurge)
        XCTAssertEqual(committedAssetDataAfterPurge, newDrawingData)
    }
}
