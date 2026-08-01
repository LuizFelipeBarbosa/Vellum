import Foundation

/// An element of a workspace collection: one JSON array in the workspace root, listed
/// in creation order.
public protocol WorkspaceCollectionElement: Codable, Sendable, Identifiable where ID == UUID {
    var createdAt: Date { get }
    /// Name of the JSON array file the whole collection lives in.
    static var collectionFileName: String { get }
}

extension Space: WorkspaceCollectionElement {
    public static let collectionFileName = "spaces.json"
}

extension Entity: WorkspaceCollectionElement {
    public static let collectionFileName = "entities.json"
}

extension TaskItem: WorkspaceCollectionElement {
    public static let collectionFileName = "tasks.json"
}

/// Spaces, entities and tasks differ only in their element type and their file name, so
/// they share one implementation. The three protocols stay separate — they are what the
/// services depend on, and what tests substitute for.
public actor FileCollectionRepository<Element: WorkspaceCollectionElement> {
    private let file: JSONArrayFile<Element>

    public init(rootDirectory: URL) {
        file = JSONArrayFile(
            fileURL: rootDirectory.appendingPathComponent(Element.collectionFileName)
        )
    }

    public func list() async throws -> [Element] {
        try file.readAll().sorted(by: Self.byCreation)
    }

    public func save(_ element: Element) async throws {
        try file.upsert(element, sortedBy: Self.byCreation)
    }

    public func delete(id: UUID) async throws {
        try file.delete(id: id, sortedBy: Self.byCreation)
    }

    private static func byCreation(_ lhs: Element, _ rhs: Element) -> Bool {
        StableOrder.ascending(lhs, rhs, by: \.createdAt)
    }
}

extension FileCollectionRepository: SpaceRepository where Element == Space {}
extension FileCollectionRepository: EntityRepository where Element == Entity {}
extension FileCollectionRepository: TaskRepository where Element == TaskItem {}

public typealias FileSpaceRepository = FileCollectionRepository<Space>
public typealias FileEntityRepository = FileCollectionRepository<Entity>
public typealias FileTaskRepository = FileCollectionRepository<TaskItem>
