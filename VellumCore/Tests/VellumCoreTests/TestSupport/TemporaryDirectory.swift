import Foundation

/// A fresh directory under the system temporary directory, created on demand.
///
/// Tests that build a repository or service against the file system need a root no other test
/// can observe — the UUID name guarantees that even when tests run concurrently or a previous
/// run leaked its root. The name prefix makes a leaked directory attributable to this suite.
enum TemporaryDirectory {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VellumCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
