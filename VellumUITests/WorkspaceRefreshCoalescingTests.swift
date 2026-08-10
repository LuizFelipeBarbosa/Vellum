import Foundation
@testable import Vellum
import VellumCore
import XCTest

private actor CountingNoteRepository: NoteRepository {
    private let wrapped: any NoteRepository
    private var listNotesCallCount = 0

    init(wrapping wrapped: any NoteRepository) {
        self.wrapped = wrapped
    }

    func listNotes(scope: NoteListScope) async throws -> [Note] {
        listNotesCallCount += 1
        return try await wrapped.listNotes(scope: scope)
    }

    func unsupportedNotes() async throws -> [UnsupportedNotePackage] {
        try await wrapped.unsupportedNotes()
    }

    func createNote(title: String) async throws -> Note {
        try await wrapped.createNote(title: title)
    }

    func insertNote(_ note: Note) async throws {
        try await wrapped.insertNote(note)
    }

    func importNote(
        _ note: Note,
        assets: [(relativePath: String, data: Data)]
    ) async throws {
        try await wrapped.importNote(note, assets: assets)
    }

    func loadNote(id: UUID) async throws -> Note {
        try await wrapped.loadNote(id: id)
    }

    func saveNote(_ note: Note) async throws {
        try await wrapped.saveNote(note)
    }

    func deleteNote(id: UUID) async throws {
        try await wrapped.deleteNote(id: id)
    }

    func purgeNote(id: UUID) async throws -> Bool {
        try await wrapped.purgeNote(id: id)
    }

    func loadAsset(noteID: UUID, relativePath: String) async throws -> Data? {
        try await wrapped.loadAsset(noteID: noteID, relativePath: relativePath)
    }

    func assetSize(noteID: UUID, relativePath: String) async throws -> Int? {
        try await wrapped.assetSize(noteID: noteID, relativePath: relativePath)
    }

    func saveAsset(_ data: Data, noteID: UUID, relativePath: String) async throws {
        try await wrapped.saveAsset(data, noteID: noteID, relativePath: relativePath)
    }

    func deleteAsset(noteID: UUID, relativePath: String) async throws {
        try await wrapped.deleteAsset(noteID: noteID, relativePath: relativePath)
    }

    func purgeUnreferencedAssets(noteID: UUID) async throws {
        try await wrapped.purgeUnreferencedAssets(noteID: noteID)
    }

    func listCallCount() -> Int {
        listNotesCallCount
    }
}

@MainActor
final class WorkspaceRefreshCoalescingTests: XCTestCase {
    private var rootDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        rootDirectory = try TemporaryDirectory.make()
    }

    override func tearDown() async throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        rootDirectory = nil
        try await super.tearDown()
    }

    func testBurstOfWorkspaceRefreshRequestsIsDeferredAndCoalesced() async throws {
        let fixture = makeFixture()
        _ = try await fixture.notes.createNote(title: "Seed")
        let model = VellumAppModel(container: fixture.container, arguments: [])
        await model.library.refresh()
        let baseline = await fixture.notes.listCallCount()

        for _ in 0..<20 {
            model.scheduleWorkspaceRefresh()
        }

        let immediateCallCount = await fixture.notes.listCallCount()
        XCTAssertEqual(immediateCallCount, baseline)

        let refreshFinished = try await waitUntil(timeout: 4) {
            let callCount = await fixture.notes.listCallCount()
            return callCount > baseline && !model.library.isLoading
        }
        XCTAssertTrue(
            refreshFinished,
            "workspace refresh did not finish after the debounce"
        )
        let finalCallCount = await fixture.notes.listCallCount()
        XCTAssertEqual(finalCallCount, baseline + 1)
    }

    func testApplyLocalUpdatePatchesSummaryWithoutWorkspaceRefresh() async throws {
        let fixture = makeFixture()
        var note = try await fixture.notes.createNote(title: "Original")
        let library = LibraryScreenModel(workspace: fixture.container.workspace)
        await library.refresh()
        let baseline = await fixture.notes.listCallCount()

        note.title = "Locally updated"
        note.updatedAt = note.updatedAt.addingTimeInterval(60)
        library.applyLocalUpdate(note)

        let finalCallCount = await fixture.notes.listCallCount()
        XCTAssertEqual(finalCallCount, baseline)
        let summary = try XCTUnwrap(
            library.summaries.first(where: { $0.id == note.id })
        )
        XCTAssertEqual(summary.title, note.title)
        XCTAssertEqual(summary.updatedAt, note.updatedAt)
    }

    func testApplyLocalUpdateResortsSummaryByUpdatedAt() async throws {
        let fixture = makeFixture()
        var olderNote = try await fixture.notes.createNote(title: "Older")
        var newerNote = try await fixture.notes.createNote(title: "Newer")
        let referenceDate = Date()
        olderNote.updatedAt = referenceDate.addingTimeInterval(-120)
        newerNote.updatedAt = referenceDate.addingTimeInterval(-60)
        try await fixture.notes.saveNote(olderNote)
        try await fixture.notes.saveNote(newerNote)
        let library = LibraryScreenModel(workspace: fixture.container.workspace)
        await library.refresh()
        XCTAssertEqual(library.summaries.map(\.id), [newerNote.id, olderNote.id])

        olderNote.updatedAt = referenceDate
        library.applyLocalUpdate(olderNote)

        let expectedIDs = [olderNote, newerNote]
            .sorted { StableOrder.descending($0, $1, by: \.updatedAt) }
            .map(\.id)
        XCTAssertEqual(library.summaries.map(\.id), expectedIDs)
        XCTAssertEqual(library.summaries.first?.id, olderNote.id)
    }

    func testApplyLocalUpdateIgnoresNoteMissingFromListing() async throws {
        let fixture = makeFixture()
        let listedNote = try await fixture.notes.createNote(title: "Listed")
        let library = LibraryScreenModel(workspace: fixture.container.workspace)
        await library.refresh()
        let originalIDs = library.summaries.map(\.id)
        let absentID = UUID()
        let absentNote = Note(
            id: absentID,
            schemaVersion: listedNote.schemaVersion,
            revision: listedNote.revision,
            layoutVersion: listedNote.layoutVersion,
            title: "Absent",
            titleOrigin: listedNote.titleOrigin,
            tags: listedNote.tags,
            createdAt: listedNote.createdAt,
            updatedAt: listedNote.updatedAt,
            pages: listedNote.pages,
            noteType: listedNote.noteType,
            spaceID: listedNote.spaceID,
            links: listedNote.links,
            backgroundStyle: listedNote.backgroundStyle,
            pageAspectRatio: listedNote.pageAspectRatio,
            pageOrientation: listedNote.pageOrientation,
            deletedAt: listedNote.deletedAt
        )

        library.applyLocalUpdate(absentNote)

        XCTAssertEqual(library.summaries.count, originalIDs.count)
        XCTAssertEqual(library.summaries.map(\.id), originalIDs)
        XCTAssertFalse(library.summaries.contains { $0.id == absentID })
    }

    private func makeFixture() -> (
        container: AppContainer,
        notes: CountingNoteRepository
    ) {
        let fileNotes = FileNoteRepository(rootDirectory: rootDirectory)
        let notes = CountingNoteRepository(wrapping: fileNotes)
        let proposals = FileProposalRepository(rootDirectory: rootDirectory)
        let activity = FileActivityRepository(rootDirectory: rootDirectory)
        let agent = HeuristicVellumAgent()
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
        let graph = KnowledgeGraphService(
            notes: notes,
            spaces: spaces,
            entities: entities
        )
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
                answerer: HeuristicAskAnswerer(),
                activity: activity
            )
        )
        return (container, notes)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () async -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            guard Date() < deadline else { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
