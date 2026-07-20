import Foundation

public actor FileActivityRepository: ActivityRepository {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func append(_ event: ActivityEvent) async throws {
        let logURL: URL
        if let noteID = event.noteID {
            let package = FilePersistence.packageURL(rootDirectory: rootDirectory, noteID: noteID)
            if FileManager.default.fileExists(atPath: package.path) {
                logURL = package.appendingPathComponent("operations/activity.jsonl")
            } else {
                logURL = rootDirectory.appendingPathComponent("activity.jsonl")
            }
        } else {
            logURL = rootDirectory.appendingPathComponent("activity.jsonl")
        }

        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var log = (try? Data(contentsOf: logURL)) ?? Data()
            if !log.isEmpty, log.last != 0x0A {
                log.append(0x0A)
            }
            log.append(try FilePersistence.encoder(prettyPrinted: false).encode(event))
            log.append(0x0A)
            try log.write(to: logURL, options: .atomic)
        } catch {
            throw VellumError.persistenceFailure("Could not append activity: \(error.localizedDescription)")
        }
    }

    public func list(noteID: UUID?) async throws -> [ActivityEvent] {
        let logURLs: [URL]
        if let noteID {
            logURLs = [
                FilePersistence.packageURL(rootDirectory: rootDirectory, noteID: noteID)
                    .appendingPathComponent("operations/activity.jsonl")
            ]
        } else {
            var allLogs = [rootDirectory.appendingPathComponent("activity.jsonl")]
            let packages = try FilePersistence.packageDirectories(rootDirectory: rootDirectory)
            allLogs.append(contentsOf: packages.map {
                $0.appendingPathComponent("operations/activity.jsonl")
            })
            logURLs = allLogs
        }

        var events: [ActivityEvent] = []
        for logURL in logURLs where FileManager.default.fileExists(atPath: logURL.path) {
            events.append(contentsOf: try readEvents(from: logURL))
        }
        return events.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
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
