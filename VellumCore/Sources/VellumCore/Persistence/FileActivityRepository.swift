import Foundation

public actor FileActivityRepository: ActivityRepository {
    private let rootDirectory: URL

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
            var log = try existingLog(at: logURL)
            if !log.isEmpty, log.last != 0x0A {
                log.append(0x0A)
            }
            log.append(try FilePersistence.encoder(prettyPrinted: false).encode(event))
            log.append(0x0A)
            try log.write(to: logURL, options: .atomic)
        } catch let error as VellumError {
            throw error
        } catch {
            throw VellumError.persistenceFailure("Could not append activity: \(error.localizedDescription)")
        }
    }

    /// The history this append has to preserve. An absent log is legitimately empty,
    /// but a log that is present and unreadable is not: the append rewrites the whole
    /// file, so treating a failed read as "empty" would replace the user's entire
    /// activity history with this one event. Refuse the append instead — a lost event
    /// is recoverable, a wiped log is not.
    private func existingLog(at url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { return Data() }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw VellumError.persistenceFailure(
                "Could not read activity log \(url.path): \(error.localizedDescription)"
            )
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

        return events.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
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
        return try readEvents(from: url)
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
                    return try FilePersistence.decoder().decode(ActivityEvent.self, from: lineData)
                }
        } catch let error as VellumError {
            throw error
        } catch {
            throw VellumError.persistenceFailure("Malformed activity log \(url.path): \(error.localizedDescription)")
        }
    }
}
