import Foundation

enum FilePersistence {
    static let packageExtension = "native-note"

    static func encoder(prettyPrinted: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO 8601 date string."
                )
            }
            return date
        }
        return decoder
    }

    static func packageURL(rootDirectory: URL, noteID: UUID) -> URL {
        rootDirectory.appendingPathComponent("\(noteID.uuidString).\(packageExtension)", isDirectory: true)
    }

    static func packageDirectories(rootDirectory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return []
        }

        do {
            return try FileManager.default.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).filter { url in
                guard url.pathExtension == packageExtension else { return false }
                return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
        } catch {
            throw VellumError.persistenceFailure("Could not scan workspace: \(error.localizedDescription)")
        }
    }

    static func validatedAssetURL(
        rootDirectory: URL,
        noteID: UUID,
        relativePath: String
    ) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw VellumError.invalidAssetPath(relativePath)
        }

        let package = packageURL(rootDirectory: rootDirectory, noteID: noteID).standardizedFileURL
        let candidate = package.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(package.path + "/") else {
            throw VellumError.invalidAssetPath(relativePath)
        }
        return candidate
    }

    static func requirePackage(rootDirectory: URL, noteID: UUID) throws -> URL {
        let package = packageURL(rootDirectory: rootDirectory, noteID: noteID)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: package.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw VellumError.noteNotFound(noteID)
        }
        return package
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch let error as VellumError {
            throw error
        } catch {
            throw VellumError.persistenceFailure("Could not write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

public actor FileNoteRepository: NoteRepository {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func listNotes(scope: NoteListScope) async throws -> [Note] {
        let packages = try FilePersistence.packageDirectories(rootDirectory: rootDirectory)
        var notes: [Note] = []
        var failures: [String] = []

        for package in packages {
            let manifest = package.appendingPathComponent("manifest.json")
            do {
                let data = try Data(contentsOf: manifest)
                let note = try FilePersistence.decoder().decode(Note.self, from: data)
                notes.append(note)
            } catch {
                failures.append(package.lastPathComponent)
            }
        }

        guard failures.isEmpty else {
            throw VellumError.persistenceFailure(
                "Unreadable or corrupt manifests in: \(failures.sorted().joined(separator: ", "))"
            )
        }

        let filteredNotes: [Note]
        switch scope {
        case .active:
            filteredNotes = notes.filter { !$0.isTrashed }
        case .trashed:
            filteredNotes = notes.filter(\.isTrashed)
        case .all:
            filteredNotes = notes
        }

        return filteredNotes.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    public func createNote(title: String) async throws -> Note {
        let noteID = UUID()
        let pageID = UUID()
        let now = Date()
        let note = Note(
            id: noteID,
            schemaVersion: Note.currentSchemaVersion,
            revision: 1,
            title: title.isEmpty ? "Untitled" : title,
            tags: [],
            createdAt: now,
            updatedAt: now,
            pages: [
                NotePage(
                    id: pageID,
                    order: 0,
                    plainText: "",
                    drawingAssetPath: "pages/\(pageID.uuidString)/drawing.data",
                    background: .blank
                )
            ]
        )

        try await insertNote(note)
        return note
    }

    public func insertNote(_ note: Note) async throws {
        let package = FilePersistence.packageURL(rootDirectory: rootDirectory, noteID: note.id)
        do {
            try FileManager.default.createDirectory(
                at: package.appendingPathComponent("pages", isDirectory: true),
                withIntermediateDirectories: true
            )
            for page in note.pages {
                try FileManager.default.createDirectory(
                    at: package.appendingPathComponent("pages/\(page.id.uuidString)", isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            for directory in ["assets", "derived", "proposals", "operations"] {
                try FileManager.default.createDirectory(
                    at: package.appendingPathComponent(directory, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            try FilePersistence.write(note, to: package.appendingPathComponent("manifest.json"))
        } catch let error as VellumError {
            try? FileManager.default.removeItem(at: package)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: package)
            throw VellumError.persistenceFailure("Could not create note: \(error.localizedDescription)")
        }
    }

    public func loadNote(id: UUID) async throws -> Note {
        let package = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: id)
        let manifest = package.appendingPathComponent("manifest.json")
        let data: Data
        do {
            data = try Data(contentsOf: manifest)
        } catch {
            throw VellumError.corruptManifest(id)
        }

        struct SchemaProbe: Decodable {
            let schemaVersion: Int
        }

        let probe: SchemaProbe
        do {
            probe = try FilePersistence.decoder().decode(SchemaProbe.self, from: data)
        } catch {
            throw VellumError.corruptManifest(id)
        }

        guard probe.schemaVersion <= Note.currentSchemaVersion else {
            throw VellumError.unsupportedSchemaVersion(
                found: probe.schemaVersion,
                supported: Note.currentSchemaVersion
            )
        }

        do {
            return try FilePersistence.decoder().decode(Note.self, from: data)
        } catch {
            throw VellumError.corruptManifest(id)
        }
    }

    public func saveNote(_ note: Note) async throws {
        let package = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: note.id)
        var normalized = note
        if normalized.schemaVersion <= Note.currentSchemaVersion {
            normalized.schemaVersion = Note.currentSchemaVersion
        }
        try FilePersistence.write(normalized, to: package.appendingPathComponent("manifest.json"))
    }

    public func deleteNote(id: UUID) async throws {
        let package = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: id)
        do {
            try FileManager.default.removeItem(at: package)
        } catch {
            throw VellumError.persistenceFailure("Could not delete note \(id.uuidString): \(error.localizedDescription)")
        }
    }

    @discardableResult
    public func purgeNote(id: UUID) async throws -> Bool {
        let package = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: id)
        let manifest = package.appendingPathComponent("manifest.json")
        let data: Data
        do {
            data = try Data(contentsOf: manifest)
        } catch {
            throw VellumError.corruptManifest(id)
        }

        let note: Note
        do {
            note = try FilePersistence.decoder().decode(Note.self, from: data)
        } catch {
            throw VellumError.corruptManifest(id)
        }

        guard note.deletedAt != nil else { return false }
        do {
            try FileManager.default.removeItem(at: package)
        } catch {
            throw VellumError.persistenceFailure("Could not delete note \(id.uuidString): \(error.localizedDescription)")
        }
        return true
    }

    public func loadAsset(noteID: UUID, relativePath: String) async throws -> Data? {
        _ = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: noteID)
        let url = try FilePersistence.validatedAssetURL(
            rootDirectory: rootDirectory,
            noteID: noteID,
            relativePath: relativePath
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw VellumError.persistenceFailure("Could not read asset \(relativePath): \(error.localizedDescription)")
        }
    }

    public func assetSize(noteID: UUID, relativePath: String) async throws -> Int? {
        _ = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: noteID)
        let url = try FilePersistence.validatedAssetURL(
            rootDirectory: rootDirectory,
            noteID: noteID,
            relativePath: relativePath
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.intValue
        } catch {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            throw VellumError.persistenceFailure(
                "Could not inspect asset \(relativePath): \(error.localizedDescription)"
            )
        }
    }

    public func saveAsset(_ data: Data, noteID: UUID, relativePath: String) async throws {
        _ = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: noteID)
        let url = try FilePersistence.validatedAssetURL(
            rootDirectory: rootDirectory,
            noteID: noteID,
            relativePath: relativePath
        )
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw VellumError.persistenceFailure("Could not write asset \(relativePath): \(error.localizedDescription)")
        }
    }
}
