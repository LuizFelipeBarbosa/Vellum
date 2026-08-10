import Foundation

public actor FileActivityRepository: ActivityRepository {
    private let rootDirectory: URL
    private var checkedLogPaths: Set<String> = []

    /// Test-visible cost accounting. `append` is the hot path: a rewrite-the-whole-file
    /// implementation makes `bytesWritten` quadratic in the event count, while an
    /// append-only one keeps it linear.
    internal private(set) var bytesWritten: Int = 0
    internal private(set) var appendCount: Int = 0

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// A note-scoped event lives in its package so it travels with the note, but some
    /// events outlive the package they describe — `notePurged` is written right after
    /// the package is removed. Those fall back to the workspace-root log, and `list`
    /// reads both sides so nothing appended here becomes unreachable.
    public func append(_ event: ActivityEvent) async throws {
        let logURL: URL
        if let noteID = event.noteID, packageExists(noteID: noteID) {
            logURL = packageLogURL(noteID: noteID)
        } else {
            logURL = workspaceLogURL
        }

        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if !FileManager.default.fileExists(atPath: logURL.path) {
                guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
                    throw VellumError.persistenceFailure("Could not create activity log \(logURL.path).")
                }
            }
            try compactLogIfNeeded(at: logURL)

            var appendedData = Data()
            let payload = try FilePersistence.encoder(prettyPrinted: false).encode(event)
            let handle = try FileHandle(forUpdating: logURL)
            do {
                let endOffset = try handle.seekToEnd()
                if endOffset > 0 {
                    try handle.seek(toOffset: endOffset - 1)
                    if try handle.read(upToCount: 1)?.first != 0x0A {
                        appendedData.append(0x0A)
                    }
                    try handle.seekToEnd()
                }
                appendedData.append(payload)
                appendedData.append(0x0A)
                try handle.write(contentsOf: appendedData)
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }

            bytesWritten += appendedData.count
            appendCount += 1
        } catch let error as VellumError {
            throw error
        } catch {
            throw VellumError.persistenceFailure("Could not append activity: \(error.localizedDescription)")
        }
    }

    public func list(noteID: UUID?) async throws -> [ActivityEvent] {
        var events: [ActivityEvent] = []
        if let noteID {
            events = try readEventsIfPresent(at: packageLogURL(noteID: noteID))
            // `append` puts a note-scoped event in the workspace log whenever the
            // package is missing, so the note's history is incomplete without the
            // root log's share of it.
            events += try readEventsIfPresent(at: workspaceLogURL)
                .filter { $0.noteID == noteID }
        } else {
            events = try readEventsIfPresent(at: workspaceLogURL)
            for package in try FilePersistence.packageDirectories(rootDirectory: rootDirectory) {
                events += try readEventsIfPresent(
                    at: package.appendingPathComponent("operations/activity.jsonl")
                )
            }
        }

        return events.sorted { StableOrder.ascending($0, $1, by: \.createdAt) }
    }

    private var workspaceLogURL: URL {
        rootDirectory.appendingPathComponent("activity.jsonl")
    }

    private func packageLogURL(noteID: UUID) -> URL {
        FilePersistence.packageURL(rootDirectory: rootDirectory, noteID: noteID)
            .appendingPathComponent("operations/activity.jsonl")
    }

    private func packageExists(noteID: UUID) -> Bool {
        FileManager.default.fileExists(
            atPath: FilePersistence.packageURL(rootDirectory: rootDirectory, noteID: noteID).path
        )
    }

    private func readEventsIfPresent(at url: URL) throws -> [ActivityEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        try compactLogIfNeeded(at: url)
        return try readEvents(from: url)
    }

    private func compactLogIfNeeded(at url: URL) throws {
        guard checkedLogPaths.insert(url.path).inserted else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let handle = try FileHandle(forReadingFrom: url)
        let tail: Data
        do {
            let fileSize = try handle.seekToEnd()
            guard fileSize > 1_024 * 1_024 else {
                try handle.close()
                return
            }

            try handle.seek(toOffset: fileSize - 512 * 1_024)
            tail = try handle.readToEnd() ?? Data()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        guard let firstNewline = tail.firstIndex(of: 0x0A) else { return }
        let retained = tail[tail.index(after: firstNewline)...]
        // Dropping the oldest history is deliberate: bounded reads matter more than
        // retaining an unbounded log produced by older builds.
        try Data(retained).write(to: url, options: .atomic)
    }

    private func readEvents(from url: URL) throws -> [ActivityEvent] {
        do {
            let data = try Data(contentsOf: url)
            guard let contents = String(data: data, encoding: .utf8) else {
                throw VellumError.persistenceFailure("Activity log \(url.path) is not UTF-8.")
            }
            return try contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .compactMap { line -> ActivityEvent? in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    guard let lineData = trimmed.data(using: .utf8) else {
                        throw VellumError.persistenceFailure("Activity log \(url.path) contains invalid text.")
                    }
                    // A torn trailing line must not cost the user their entire history.
                    return try? FilePersistence.decoder().decode(ActivityEvent.self, from: lineData)
                }
        } catch let error as VellumError {
            throw error
        } catch {
            throw VellumError.persistenceFailure("Malformed activity log \(url.path): \(error.localizedDescription)")
        }
    }
}
