import Foundation

public actor FileSpaceRepository: SpaceRepository {
    private let file: JSONArrayFile<Space>

    public init(rootDirectory: URL) {
        file = JSONArrayFile(fileURL: rootDirectory.appendingPathComponent("spaces.json"))
    }

    public func list() async throws -> [Space] {
        try file.readAll().sorted(by: Self.sort)
    }

    public func save(_ space: Space) async throws {
        try file.upsert(space, sortedBy: Self.sort)
    }

    public func delete(id: UUID) async throws {
        try file.delete(id: id, sortedBy: Self.sort)
    }

    private static func sort(_ lhs: Space, _ rhs: Space) -> Bool {
        StableOrder.ascending(lhs, rhs, by: \.createdAt)
    }
}
