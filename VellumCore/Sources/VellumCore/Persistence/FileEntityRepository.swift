import Foundation

public actor FileEntityRepository: EntityRepository {
    private let file: JSONArrayFile<Entity>

    public init(rootDirectory: URL) {
        file = JSONArrayFile(fileURL: rootDirectory.appendingPathComponent("entities.json"))
    }

    public func list() async throws -> [Entity] {
        try file.readAll().sorted(by: Self.sort)
    }

    public func save(_ entity: Entity) async throws {
        try file.upsert(entity, sortedBy: Self.sort)
    }

    public func delete(id: UUID) async throws {
        try file.delete(id: id, sortedBy: Self.sort)
    }

    private static func sort(_ lhs: Entity, _ rhs: Entity) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }
}
