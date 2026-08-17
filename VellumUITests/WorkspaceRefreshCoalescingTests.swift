import Foundation
@testable import Vellum
import VellumCore
import XCTest

private actor CountingNoteRepository: NoteRepository {
    private let wrapped: any NoteRepository
    private var listNotesCallCount = 0
    private var listTrashedNotesCallCount = 0

    init(wrapping wrapped: any NoteRepository) {
        self.wrapped = wrapped
    }

    func listNotes(scope: NoteListScope) async throws -> [Note] {
        let notes = try await wrapped.listNotes(scope: scope)
        switch scope {
        case .active:
            listNotesCallCount += 1
        case .trashed:
            listTrashedNotesCallCount += 1
        case .all:
            break
        }
        return notes
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

    func destroyNotePackage(id: UUID) async throws {
        try await wrapped.destroyNotePackage(id: id)
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

    func trashedListCallCount() -> Int {
        listTrashedNotesCallCount
    }
}

private actor CountingTaskRepository: TaskRepository {
    private let wrapped: any TaskRepository
    private var listTasksCallCount = 0

    init(wrapping wrapped: any TaskRepository) {
        self.wrapped = wrapped
    }

    func list() async throws -> [TaskItem] {
        let tasks = try await wrapped.list()
        listTasksCallCount += 1
        return tasks
    }

    func save(_ task: TaskItem) async throws {
        try await wrapped.save(task)
    }

    func delete(id: UUID) async throws {
        try await wrapped.delete(id: id)
    }

    func listCallCount() -> Int {
        listTasksCallCount
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
        model.workspaceRefreshDebounce = .milliseconds(50)
        await model.library.refresh()
        let baseline = await fixture.notes.listCallCount()
        let taskListBaseline = await fixture.tasks.listCallCount()
        let trashedListBaseline = await fixture.notes.trashedListCallCount()

        for _ in 0..<20 {
            model.scheduleWorkspaceRefresh()
        }

        let immediateCallCount = await fixture.notes.listCallCount()
        XCTAssertEqual(immediateCallCount, baseline)

        let refreshFinished = try await waitUntil(timeout: 1) {
            let callCount = await fixture.notes.listCallCount()
            let taskListCallCount = await fixture.tasks.listCallCount()
            let trashedListCallCount = await fixture.notes.trashedListCallCount()
            return callCount > baseline
                && taskListCallCount > taskListBaseline
                && trashedListCallCount > trashedListBaseline
                && !model.library.isLoading
        }
        XCTAssertTrue(
            refreshFinished,
            "workspace refresh did not finish after the debounce"
        )
        let finalCallCount = await fixture.notes.listCallCount()
        XCTAssertEqual(finalCallCount, baseline + 1)
    }

    func testContinuousWorkspaceRefreshRequestsCannotStarveRefreshOrCounts() async throws {
        let fixture = makeFixture()
        _ = try await fixture.notes.createNote(title: "Seed")
        let model = VellumAppModel(container: fixture.container, arguments: [])
        model.workspaceRefreshDebounce = .milliseconds(50)
        model.workspaceRefreshMaxLatency = .milliseconds(200)
        await model.library.refresh()
        let noteListBaseline = await fixture.notes.listCallCount()
        let taskListBaseline = await fixture.tasks.listCallCount()
        var refreshedDuringRearming = false
        var countsRefreshedDuringRearming = false

        for _ in 0..<24 {
            model.scheduleWorkspaceRefresh()
            try await Task.sleep(for: .milliseconds(25))

            let noteListCallCount = await fixture.notes.listCallCount()
            let taskListCallCount = await fixture.tasks.listCallCount()
            refreshedDuringRearming = refreshedDuringRearming
                || noteListCallCount > noteListBaseline
            countsRefreshedDuringRearming = countsRefreshedDuringRearming
                || taskListCallCount > taskListBaseline
        }

        XCTAssertTrue(
            refreshedDuringRearming,
            "library refresh was starved by continuous debounce re-arming"
        )
        XCTAssertTrue(
            countsRefreshedDuringRearming,
            "sidebar counts were not refreshed during the bounded-latency window"
        )
    }

    func testApplyLocalUpdateOverridesAndPreservesHasInkSynchronously() async throws {
        let fixture = makeFixture()
        var note = try await fixture.notes.createNote(title: "Ink fidelity")
        let library = LibraryScreenModel(workspace: fixture.container.workspace)
        await library.refresh()
        XCTAssertEqual(library.summaries.first(where: { $0.id == note.id })?.hasInk, false)

        library.applyLocalUpdate(note, hasInk: true)

        XCTAssertEqual(library.summaries.first(where: { $0.id == note.id })?.hasInk, true)

        note.title = "Preserve the override"
        library.applyLocalUpdate(note)

        XCTAssertEqual(library.summaries.first(where: { $0.id == note.id })?.hasInk, true)
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
        notes: CountingNoteRepository,
        tasks: CountingTaskRepository
    ) {
        let fileNotes = FileNoteRepository(rootDirectory: rootDirectory)
        let notes = CountingNoteRepository(wrapping: fileNotes)
        let proposals = FileProposalRepository(rootDirectory: rootDirectory)
        let activity = FileActivityRepository(rootDirectory: rootDirectory)
        let agent = HeuristicVellumAgent()
        let spaces = FileSpaceRepository(rootDirectory: rootDirectory)
        let entities = FileEntityRepository(rootDirectory: rootDirectory)
        let fileTasks = FileTaskRepository(rootDirectory: rootDirectory)
        let tasks = CountingTaskRepository(wrapping: fileTasks)
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
        return (container, notes, tasks)
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
