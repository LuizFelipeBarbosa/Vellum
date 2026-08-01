import Foundation

enum FilePersistence {
    static let packageExtension = "native-note"

    static func encoder(prettyPrinted: Bool = true) -> JSONEncoder {
        VellumJSONCoding.encoder(
            outputFormatting: prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        )
    }

    static func decoder() -> JSONDecoder {
        VellumJSONCoding.decoder()
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
        try validatedAssetURL(
            package: packageURL(rootDirectory: rootDirectory, noteID: noteID),
            relativePath: relativePath
        )
    }

    static func validatedAssetURL(
        package: URL,
        relativePath: String
    ) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw VellumError.invalidAssetPath(relativePath)
        }

        let standardizedPackage = package.standardizedFileURL
        let candidate = standardizedPackage.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(standardizedPackage.path + "/") else {
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

private struct SchemaProbe: Decodable {
    let schemaVersion: Int
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
                let probe = try FilePersistence.decoder().decode(SchemaProbe.self, from: data)
                guard probe.schemaVersion <= Note.currentSchemaVersion else { continue }
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

        return filteredNotes.sorted { StableOrder.descending($0, $1, by: \.updatedAt) }
    }

    public func unsupportedNotes() async throws -> [UnsupportedNotePackage] {
        let packages = try FilePersistence.packageDirectories(rootDirectory: rootDirectory)
        var unsupportedPackages: [UnsupportedNotePackage] = []

        for package in packages {
            let manifest = package.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifest),
                  let probe = try? FilePersistence.decoder().decode(SchemaProbe.self, from: data),
                  probe.schemaVersion > Note.currentSchemaVersion else {
                continue
            }
            unsupportedPackages.append(
                UnsupportedNotePackage(
                    packageName: package.lastPathComponent,
                    schemaVersion: probe.schemaVersion
                )
            )
        }

        return unsupportedPackages.sorted { $0.packageName < $1.packageName }
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
            ],
            backgroundStyle: .blank
        )

        try await insertNote(note)
        return note
    }

    public func insertNote(_ note: Note) async throws {
        do {
            try stageAndInstallPackage(for: note, assets: [])
        } catch let error as VellumError {
            throw error
        } catch {
            throw VellumError.persistenceFailure("Could not create note: \(error.localizedDescription)")
        }
    }

    public func importNote(
        _ note: Note,
        assets: [(relativePath: String, data: Data)]
    ) async throws {
        try stageAndInstallPackage(for: note, assets: assets)
    }

    public func loadNote(id: UUID) async throws -> Note {
        try decodedManifest(id: id, requireSupportedSchema: true)
    }

    /// Reads and decodes a note's manifest, reporting every failure as a corrupt manifest.
    ///
    /// `requireSupportedSchema` is on for reads and off for `purgeNote`. Reads are
    /// fail-closed so a note written by a newer build is never silently downgraded by
    /// decoding it against today's model. Purge is not a read: it destroys the package
    /// wholesale, and refusing it on schema grounds would leave a forward-schema note
    /// permanently stuck in the workspace with no path that can remove it.
    private func decodedManifest(id: UUID, requireSupportedSchema: Bool) throws -> Note {
        let package = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: id)
        let manifest = package.appendingPathComponent("manifest.json")
        let data: Data
        do {
            data = try Data(contentsOf: manifest)
        } catch {
            throw VellumError.corruptManifest(id)
        }

        if requireSupportedSchema {
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
        }

        do {
            return try FilePersistence.decoder().decode(Note.self, from: data)
        } catch {
            throw VellumError.corruptManifest(id)
        }
    }

    public func saveNote(_ note: Note) async throws {
        let package = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: note.id)
        guard note.schemaVersion <= Note.currentSchemaVersion else {
            throw VellumError.unsupportedSchemaVersion(
                found: note.schemaVersion,
                supported: Note.currentSchemaVersion
            )
        }
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
        // Schema-unchecked on purpose: purge must stay able to remove a note this build
        // cannot load. See `decodedManifest`.
        let note = try decodedManifest(id: id, requireSupportedSchema: false)
        guard note.deletedAt != nil else { return false }
        let package = FilePersistence.packageURL(rootDirectory: rootDirectory, noteID: id)
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

    public func deleteAsset(noteID: UUID, relativePath: String) async throws {
        _ = try FilePersistence.requirePackage(rootDirectory: rootDirectory, noteID: noteID)
        let url = try FilePersistence.validatedAssetURL(
            rootDirectory: rootDirectory,
            noteID: noteID,
            relativePath: relativePath
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw VellumError.persistenceFailure(
                "Could not delete asset \(relativePath): \(error.localizedDescription)"
            )
        }
    }

    public func purgeUnreferencedAssets(noteID: UUID) async throws {
        let fileManager = FileManager.default
        let package = FilePersistence.packageURL(rootDirectory: rootDirectory, noteID: noteID)
        var isPackageDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: package.path, isDirectory: &isPackageDirectory),
              isPackageDirectory.boolValue else {
            return
        }

        let manifest = package.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifest),
              let probe = try? FilePersistence.decoder().decode(SchemaProbe.self, from: data),
              probe.schemaVersion <= Note.currentSchemaVersion,
              let note = try? FilePersistence.decoder().decode(Note.self, from: data) else {
            return
        }

        var referencedPaths = Set(note.pages.map(\.drawingAssetPath))
        for page in note.pages {
            if let pdfAssetPath = page.pdfPage?.assetPath {
                referencedPaths.insert(pdfAssetPath)
            }
            for element in page.elements {
                guard case .image(let content) = element.content else { continue }
                referencedPaths.insert(content.assetPath)
            }
        }

        let pages = package.appendingPathComponent("pages", isDirectory: true)
        var isPagesDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: pages.path, isDirectory: &isPagesDirectory),
              isPagesDirectory.boolValue,
              let pageDirectories = try? fileManager.contentsOfDirectory(
                  at: pages,
                  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for pageDirectory in pageDirectories {
            guard let pageValues = try? pageDirectory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ),
            pageValues.isDirectory == true,
            pageValues.isSymbolicLink != true,
            let assets = try? fileManager.contentsOfDirectory(
                at: pageDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for asset in assets {
                let filename = asset.lastPathComponent
                guard filename.hasPrefix("drawing"),
                      filename.hasSuffix(".data"),
                      let assetValues = try? asset.resourceValues(
                          forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                      ),
                      assetValues.isDirectory != true,
                      assetValues.isSymbolicLink != true else {
                    continue
                }

                let relativePath = "pages/\(pageDirectory.lastPathComponent)/\(filename)"
                guard !referencedPaths.contains(relativePath) else { continue }
                try? fileManager.removeItem(at: asset)
            }
        }

        let importedAssets = package.appendingPathComponent("assets", isDirectory: true)
        var isAssetsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: importedAssets.path, isDirectory: &isAssetsDirectory),
           isAssetsDirectory.boolValue,
           let assets = try? fileManager.contentsOfDirectory(
               at: importedAssets,
               includingPropertiesForKeys: [
                   .isRegularFileKey,
                   .isDirectoryKey,
                   .isSymbolicLinkKey,
               ],
               options: [.skipsHiddenFiles]
           ) {
            for asset in assets {
                guard let assetValues = try? asset.resourceValues(
                    forKeys: [
                        .isRegularFileKey,
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ]
                ),
                assetValues.isRegularFile == true,
                assetValues.isDirectory != true,
                assetValues.isSymbolicLink != true else {
                    continue
                }

                let relativePath = "assets/\(asset.lastPathComponent)"
                guard !referencedPaths.contains(relativePath) else { continue }
                try? fileManager.removeItem(at: asset)
            }
        }
    }

    /// Builds the whole package under a hidden staging name and moves it into place
    /// in one step, so the workspace only ever sees a finished package. `listNotes`
    /// is fail-closed — a single torn package makes the entire library unreadable —
    /// and a write interrupted partway leaves nothing behind but staging, which the
    /// scan skips as hidden.
    private func stageAndInstallPackage(
        for note: Note,
        assets: [(relativePath: String, data: Data)]
    ) throws {
        let fileManager = FileManager.default
        let finalPackage = FilePersistence.packageURL(
            rootDirectory: rootDirectory,
            noteID: note.id
        )
        let stagingPackage = rootDirectory.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true
            )
            try createPackage(for: note, at: stagingPackage)
            for asset in assets {
                let url = try FilePersistence.validatedAssetURL(
                    package: stagingPackage,
                    relativePath: asset.relativePath
                )
                try fileManager.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try asset.data.write(to: url, options: .atomic)
            }
            try fileManager.moveItem(at: stagingPackage, to: finalPackage)
        } catch {
            try? fileManager.removeItem(at: stagingPackage)
            throw error
        }
    }

    private func createPackage(for note: Note, at package: URL) throws {
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("pages", isDirectory: true),
            withIntermediateDirectories: true
        )
        for page in note.pages {
            try FileManager.default.createDirectory(
                at: package.appendingPathComponent(
                    "pages/\(page.id.uuidString)",
                    isDirectory: true
                ),
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
    }
}
