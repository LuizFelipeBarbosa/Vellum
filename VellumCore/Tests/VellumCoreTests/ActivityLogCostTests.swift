/**
 `activityAppendCostIsLinearInEventCount` guards the append-only activity-log implementation against
 regressing to a whole-file rewrite on every event.

 `repeatedSavesDoNotFloodTheActivityLog` is expected to fail until save activity is coalesced or
 throttled in the workspace service.
 */
import Foundation
import Testing
@testable import VellumCore

@Test
func activityAppendCostIsLinearInEventCount() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = FileActivityRepository(rootDirectory: root)

    for index in 0..<400 {
        try await repo.append(
            ActivityEvent(
                id: UUID(),
                noteID: nil,
                createdAt: Date(),
                kind: .noteUpdated,
                message: "Update \(index)"
            )
        )
    }

    let written = await repo.bytesWritten
    // A single serialized ActivityEvent line is roughly 250 bytes. 400 appends that
    // each write only the new event (linear) total roughly 400 * 250 ~= 100 KB.
    // 400 * 400 = 160,000 leaves comfortable room for serialized event size while
    // still catching the quadratic cost of rewriting the whole log on every append.
    #expect(written < 400 * 400)
    #expect(await repo.appendCount == 400)
}

@Test
func activityLogIgnoresATornFinalLine() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = FileActivityRepository(rootDirectory: root)
    let events = (0..<3).map { index in
        ActivityEvent(
            id: UUID(),
            noteID: nil,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            kind: .noteUpdated,
            message: "Update \(index)"
        )
    }

    for event in events {
        try await repo.append(event)
    }

    let logURL = root.appendingPathComponent("activity.jsonl")
    let handle = try FileHandle(forWritingTo: logURL)
    do {
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"truncated".utf8))
        try handle.close()
    } catch {
        try? handle.close()
        throw error
    }

    let listed = try await repo.list(noteID: nil)
    #expect(listed.map(\.id) == events.map(\.id))
}

@Test
func oversizedActivityLogIsCompactedToCompleteTailLines() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let logURL = root.appendingPathComponent("activity.jsonl")
    let event = ActivityEvent(
        id: UUID(),
        noteID: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        kind: .noteUpdated,
        message: String(repeating: "x", count: 256)
    )
    var line = try FilePersistence.encoder(prettyPrinted: false).encode(event)
    line.append(0x0A)
    var oversizedLog = Data()
    while oversizedLog.count <= 2 * 1_024 * 1_024 {
        oversizedLog.append(line)
    }
    try oversizedLog.write(to: logURL)

    let repo = FileActivityRepository(rootDirectory: root)
    let listed = try await repo.list(noteID: nil)
    let compactedLog = try Data(contentsOf: logURL)

    #expect(compactedLog.count <= 512 * 1_024)
    #expect(!listed.isEmpty)

    let contents = try #require(String(data: compactedLog, encoding: .utf8))
    for survivingLine in contents.split(separator: "\n") {
        _ = try FilePersistence.decoder().decode(
            ActivityEvent.self,
            from: Data(survivingLine.utf8)
        )
    }
}

@Test
func repeatedSavesDoNotFloodTheActivityLog() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = WorkspaceService(
        notes: FileNoteRepository(rootDirectory: root),
        proposals: FileProposalRepository(rootDirectory: root),
        activity: FileActivityRepository(rootDirectory: root),
        agent: HeuristicVellumAgent(),
        spaces: FileSpaceRepository(rootDirectory: root),
        entities: FileEntityRepository(rootDirectory: root),
        tasks: FileTaskRepository(rootDirectory: root)
    )
    var note = try await service.createNote(title: "Autosave")

    for _ in 0..<100 {
        note = try await service.saveNote(note)
    }

    let events = try await service.activity(noteID: note.id)
    let updates = events.filter { $0.kind == .noteUpdated }
    #expect(updates.count <= 5)
}

@Test
func libraryListingScansTheWorkspaceOnce() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let notes = CountingNoteRepository(
        wrapping: FileNoteRepository(rootDirectory: root)
    )
    let service = WorkspaceService(
        notes: notes,
        proposals: FileProposalRepository(rootDirectory: root),
        activity: FileActivityRepository(rootDirectory: root),
        agent: HeuristicVellumAgent(),
        spaces: FileSpaceRepository(rootDirectory: root),
        entities: FileEntityRepository(rootDirectory: root),
        tasks: FileTaskRepository(rootDirectory: root)
    )
    _ = try await service.createNote(title: "Library seed")
    _ = try await service.createSpace(name: "Seed space", color: .blue)

    let listing = try await service.libraryListing()

    #expect(listing.summaries.count == 1)
    #expect(listing.spaces.count == 1)
    #expect(await notes.listNotesCallCount == 1)
}

@Test
func activityOverviewReadsTheCorpusOnce() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: root) }
    let activity = CountingActivityRepository(
        wrapping: FileActivityRepository(rootDirectory: root)
    )
    let service = WorkspaceService(
        notes: FileNoteRepository(rootDirectory: root),
        proposals: FileProposalRepository(rootDirectory: root),
        activity: activity,
        agent: HeuristicVellumAgent(),
        spaces: FileSpaceRepository(rootDirectory: root),
        entities: FileEntityRepository(rootDirectory: root),
        tasks: FileTaskRepository(rootDirectory: root)
    )
    _ = try await service.createNote(title: "Activity seed")

    let overview = try await service.activityOverview(
        since: .distantPast,
        highlighting: [.noteCreated]
    )

    #expect(overview.latestMessage == "Created note 'Activity seed'.")
    #expect(overview.digest.countsByKind[.noteCreated] == 1)
    #expect(await activity.listCallCount == 1)
}

private actor CountingNoteRepository: NoteRepository {
    private let wrapped: any NoteRepository
    private(set) var listNotesCallCount = 0

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
}

private actor CountingActivityRepository: ActivityRepository {
    private let wrapped: any ActivityRepository
    private(set) var listCallCount = 0

    init(wrapping wrapped: any ActivityRepository) {
        self.wrapped = wrapped
    }

    func append(_ event: ActivityEvent) async throws {
        try await wrapped.append(event)
    }

    func list(noteID: UUID?) async throws -> [ActivityEvent] {
        listCallCount += 1
        return try await wrapped.list(noteID: noteID)
    }
}
