import Foundation

public actor FileTaskRepository: TaskRepository {
    private let file: JSONArrayFile<TaskItem>

    public init(rootDirectory: URL) {
        file = JSONArrayFile(fileURL: rootDirectory.appendingPathComponent("tasks.json"))
    }

    public func list() async throws -> [TaskItem] {
        try file.readAll().sorted(by: Self.sort)
    }

    public func save(_ task: TaskItem) async throws {
        try file.upsert(task, sortedBy: Self.sort)
    }

    public func delete(id: UUID) async throws {
        try file.delete(id: id, sortedBy: Self.sort)
    }

    private static func sort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        StableOrder.ascending(lhs, rhs, by: \.createdAt)
    }
}
