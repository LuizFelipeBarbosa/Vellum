import Foundation

public struct WorkspaceSeeder: Sendable {
    private static let workspaceSeededEventID = UUID(
        uuidString: "70000000-0000-4000-8000-000000000011"
    )!

    private struct SeedState: Codable, Sendable {
        let seedVersion: Int
        let seededAt: Date
    }

    private let rootDirectory: URL
    private let notes: any NoteRepository
    private let spaces: any SpaceRepository
    private let entities: any EntityRepository
    private let tasks: any TaskRepository
    private let activity: any ActivityRepository

    public init(
        rootDirectory: URL,
        notes: any NoteRepository,
        spaces: any SpaceRepository,
        entities: any EntityRepository,
        tasks: any TaskRepository,
        activity: any ActivityRepository
    ) {
        self.rootDirectory = rootDirectory
        self.notes = notes
        self.spaces = spaces
        self.entities = entities
        self.tasks = tasks
        self.activity = activity
    }

    @discardableResult
    public func seedIfNeeded(now: Date = Date()) async throws -> Bool {
        let markerURL = rootDirectory.appendingPathComponent("seed-state.json")
        guard !FileManager.default.fileExists(atPath: markerURL.path) else {
            return false
        }
        guard try FilePersistence.packageDirectories(rootDirectory: rootDirectory).isEmpty else {
            return false
        }

        let bundle = SeedContent.demo(now: now)
        for space in bundle.spaces {
            try await spaces.save(space)
        }
        for note in bundle.notes {
            try await notes.insertNote(note)
        }
        for entity in bundle.entities {
            try await entities.save(entity)
        }
        for task in bundle.tasks {
            try await tasks.save(task)
        }
        for event in bundle.activity {
            try await activity.append(event)
        }
        try await activity.append(
            ActivityEvent(
                id: Self.workspaceSeededEventID,
                noteID: nil,
                createdAt: now,
                kind: .workspaceSeeded,
                message: "Seeded the demo workspace."
            )
        )

        try FilePersistence.write(
            SeedState(seedVersion: 1, seededAt: now),
            to: markerURL
        )
        return true
    }
}
