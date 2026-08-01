import Foundation

/// A fresh directory under the system temporary directory, created on demand.
///
/// Tests that stand up a live `AppContainer` need a root no other test can observe — the UUID
/// name guarantees that even when tests run concurrently or a previous run leaked its root.
enum TemporaryDirectory {
    static func make() throws -> URL {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        return rootDirectory
    }
}
