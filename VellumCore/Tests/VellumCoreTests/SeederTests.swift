import Foundation
import Testing
@testable import VellumCore

@Suite("Workspace seeding")
struct SeederTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test("First run creates the complete demo workspace and loadable notes")
    func firstRunSeedsWorkspace() async throws {
        let fixture = try SeederFixture()
        defer { fixture.cleanup() }

        #expect(try await fixture.seeder.seedIfNeeded(now: now))

        let notes = try await fixture.notes.listNotes()
        #expect(notes.count == 8)
        #expect(try await fixture.spaces.list().count == 4)
        #expect(try await fixture.entities.list().count == 4)
        #expect(try await fixture.tasks.list().count == 4)
        for note in notes {
            let loaded = try await fixture.notes.loadNote(id: note.id)
            #expect(loaded.id == note.id)
        }
        #expect(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("seed-state.json").path
        ))
    }

    @Test("Second run is a no-op and leaves note manifests untouched")
    func secondRunDoesNotReseed() async throws {
        let fixture = try SeederFixture()
        defer { fixture.cleanup() }
        #expect(try await fixture.seeder.seedIfNeeded(now: now))
        let notes = try await fixture.notes.listNotes()
        let before = try manifestModificationDates(root: fixture.root, notes: notes)

        #expect(try await fixture.seeder.seedIfNeeded(now: now.addingTimeInterval(60)) == false)

        let after = try manifestModificationDates(root: fixture.root, notes: notes)
        #expect(after == before)
        #expect(try await fixture.notes.listNotes().count == 8)
    }

    @Test("An existing native note package prevents seeding")
    func existingNotePackagePreventsSeeding() async throws {
        let fixture = try SeederFixture()
        defer { fixture.cleanup() }
        let manualPackage = fixture.root.appendingPathComponent(
            "manual.native-note",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: manualPackage,
            withIntermediateDirectories: true
        )

        #expect(try await fixture.seeder.seedIfNeeded(now: now) == false)

        #expect(!FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("seed-state.json").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("spaces.json").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("entities.json").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("tasks.json").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("activity.jsonl").path
        ))
    }

    @Test("Seeded data supports graph, ask, and activity services")
    func seededDataIntegratesWithServices() async throws {
        let fixture = try SeederFixture()
        defer { fixture.cleanup() }
        #expect(try await fixture.seeder.seedIfNeeded(now: now))

        let graph = KnowledgeGraphService(
            notes: fixture.notes,
            spaces: fixture.spaces,
            entities: fixture.entities
        )
        let snapshot = try await graph.snapshot()
        let nodeIDs = Set(snapshot.nodes.map(\.id))
        #expect(snapshot.nodes.count >= 16)
        #expect(snapshot.edges.allSatisfy {
            nodeIDs.contains($0.source) && nodeIDs.contains($0.target)
        })

        let seededNotes = try await fixture.notes.listNotes()
        let permit = try #require(seededNotes.first {
            $0.title == "Permit application #2231"
        })
        let ask = AskService(
            notes: fixture.notes,
            answerer: HeuristicAskAnswerer(),
            activity: nil
        )
        let answer = try await ask.ask("What did Marco quote for the steel beam?")
        let firstCitation = try #require(answer.citations.first)
        #expect(firstCitation.noteID == permit.id)

        let workspace = WorkspaceService(
            notes: fixture.notes,
            proposals: fixture.proposals,
            activity: fixture.activity,
            agent: HeuristicVellumAgent(),
            spaces: fixture.spaces,
            entities: fixture.entities,
            tasks: fixture.tasks
        )
        let digest = try await workspace.activityDigest(
            since: now.addingTimeInterval(-2 * 86_400)
        )
        #expect(digest.totalAgentActions > 0)
    }
}

private struct SeederFixture {
    let root: URL
    let notes: FileNoteRepository
    let proposals: FileProposalRepository
    let activity: FileActivityRepository
    let spaces: FileSpaceRepository
    let entities: FileEntityRepository
    let tasks: FileTaskRepository

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VellumCoreSeederTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        notes = FileNoteRepository(rootDirectory: root)
        proposals = FileProposalRepository(rootDirectory: root)
        activity = FileActivityRepository(rootDirectory: root)
        spaces = FileSpaceRepository(rootDirectory: root)
        entities = FileEntityRepository(rootDirectory: root)
        tasks = FileTaskRepository(rootDirectory: root)
    }

    var seeder: WorkspaceSeeder {
        WorkspaceSeeder(
            rootDirectory: root,
            notes: notes,
            spaces: spaces,
            entities: entities,
            tasks: tasks,
            activity: activity
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func manifestModificationDates(root: URL, notes: [Note]) throws -> [UUID: Date] {
    var dates: [UUID: Date] = [:]
    for note in notes {
        let manifest = FilePersistence.packageURL(rootDirectory: root, noteID: note.id)
            .appendingPathComponent("manifest.json")
        let modifiedAt = try manifest.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        dates[note.id] = modifiedAt
    }
    return dates
}
