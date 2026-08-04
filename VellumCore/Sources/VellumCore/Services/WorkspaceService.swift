import Foundation

public actor WorkspaceService {
    private let notes: any NoteRepository
    private let proposals: any AgentProposalRepository
    private let activityRepository: any ActivityRepository
    private let agent: any VellumAgent
    private let spaces: any SpaceRepository
    private let entities: any EntityRepository
    private let tasks: any TaskRepository

    public init(
        notes: any NoteRepository,
        proposals: any AgentProposalRepository,
        activity: any ActivityRepository,
        agent: any VellumAgent,
        spaces: any SpaceRepository,
        entities: any EntityRepository,
        tasks: any TaskRepository
    ) {
        self.notes = notes
        self.proposals = proposals
        self.activityRepository = activity
        self.agent = agent
        self.spaces = spaces
        self.entities = entities
        self.tasks = tasks
    }

    public func listNotes() async throws -> [Note] {
        try await notes.listNotes()
    }

    public func unsupportedNotes() async throws -> [UnsupportedNotePackage] {
        try await notes.unsupportedNotes()
    }

    public func loadNote(id: UUID) async throws -> Note {
        try await notes.loadNote(id: id)
    }

    public func createNote(title: String) async throws -> Note {
        let note = try await notes.createNote(title: title)
        try await log(
            noteID: note.id,
            kind: .noteCreated,
            message: "Created note '\(note.title)'."
        )
        return note
    }

    public func importNote(
        _ note: Note,
        assets: [(relativePath: String, data: Data)]
    ) async throws {
        try await notes.importNote(note, assets: assets)
    }

    public func saveAsset(_ data: Data, noteID: UUID, relativePath: String) async throws {
        try await notes.saveAsset(data, noteID: noteID, relativePath: relativePath)
    }

    @discardableResult
    public func saveNote(_ note: Note) async throws -> Note {
        let persisted = try await notes.loadNote(id: note.id)
        var saved = note
        saved.deletedAt = persisted.deletedAt
        saved.updatedAt = Date()
        saved.revision += 1
        try await notes.saveNote(saved)
        try await log(
            noteID: saved.id,
            kind: .noteUpdated,
            message: "Updated note '\(saved.title)' to revision \(saved.revision)."
        )
        return saved
    }

    public func deleteNote(id: UUID) async throws {
        let note = try await notes.loadNote(id: id)
        if note.isTrashed {
            return
        }
        try await trashNote(note)
    }

    @discardableResult
    public func deleteNotes(ids: [UUID]) async throws -> [UUID] {
        var trashedIDs: [UUID] = []
        for id in ids {
            let note: Note
            do {
                note = try await notes.loadNote(id: id)
            } catch VellumError.noteNotFound {
                continue
            }
            if note.isTrashed {
                continue
            }
            try await trashNote(note)
            trashedIDs.append(id)
        }
        return trashedIDs
    }

    @discardableResult
    public func restoreNote(id: UUID) async throws -> Note {
        var note = try await notes.loadNote(id: id)
        note.deletedAt = nil
        try await notes.saveNote(note)
        try await log(
            noteID: id,
            kind: .noteRestored,
            message: "Restored note \(id.uuidString) from Trash."
        )
        return note
    }

    public func restoreNotes(ids: [UUID]) async throws {
        for id in ids {
            do {
                try await restoreNote(id: id)
            } catch VellumError.noteNotFound {
                continue
            }
        }
    }

    public func purgeNote(id: UUID) async throws {
        guard try await notes.purgeNote(id: id) else { return }
        for task in try await tasks.list() where task.noteID == id {
            try await tasks.delete(id: task.id)
        }
        for var entity in try await entities.list() {
            entity.sources.removeAll { $0.noteID == id }
            if entity.sources.isEmpty {
                try await entities.delete(id: entity.id)
            } else {
                try await entities.save(entity)
            }
        }
        try await log(
            noteID: id,
            kind: .notePurged,
            message: "Permanently deleted note \(id.uuidString)."
        )
    }

    public func emptyTrash() async throws {
        for note in try await listTrashedNotes() {
            try await purgeNote(id: note.id)
        }
    }

    public func listTrashedNotes() async throws -> [Note] {
        // Everything in this scope has a `deletedAt`; the fallback only keeps the key
        // comparable.
        try await notes.listNotes(scope: .trashed).sorted {
            StableOrder.descending($0, $1, by: { $0.deletedAt ?? .distantPast })
        }
    }

    public func listSpaces() async throws -> [SpaceListing] {
        let listedNotes = try await notes.listNotes()
        return try await spaces.list().map { space in
            SpaceListing(
                space: space,
                noteCount: listedNotes.count { $0.spaceID == space.id }
            )
        }
    }

    @discardableResult
    public func createSpace(
        name: String,
        color: SpaceColor,
        parentID: UUID? = nil
    ) async throws -> Space {
        if let parentID {
            let allSpaces = try await spaces.list()
            guard let parent = allSpaces.first(where: { $0.id == parentID }) else {
                throw VellumError.spaceNotFound(parentID)
            }
            guard parent.parentID == nil else {
                throw VellumError.invalidSubspaceNesting
            }
        }
        let space = Space(
            id: UUID(),
            name: name,
            color: color,
            createdAt: Date(),
            parentID: parentID
        )
        try await spaces.save(space)
        try await log(noteID: nil, kind: .spaceCreated, message: "Created space '\(name)'.")
        return space
    }

    public func deleteSpace(id: UUID) async throws {
        let allSpaces = try await spaces.list()
        guard let target = allSpaces.first(where: { $0.id == id }) else {
            throw VellumError.spaceNotFound(id)
        }
        let childIDs = allSpaces.filter { $0.parentID == id }.map(\.id)
        let doomedIDs = Set([id] + childIDs)
        let doomedNotes = try await notes.listNotes().filter { note in
            guard let spaceID = note.spaceID else { return false }
            return doomedIDs.contains(spaceID)
        }

        for note in doomedNotes {
            try await trashNote(note)
        }
        for var note in try await notes.listNotes(scope: .all) {
            guard let spaceID = note.spaceID, doomedIDs.contains(spaceID) else { continue }
            note.spaceID = nil
            try await notes.saveNote(note)
        }
        for doomedID in childIDs + [id] {
            try await spaces.delete(id: doomedID)
        }
        try await log(
            noteID: nil,
            kind: .spaceDeleted,
            message: "Deleted space '\(target.name)' (\(childIDs.count) subspaces, \(doomedNotes.count) notes trashed)."
        )
    }

    @discardableResult
    public func assignNote(id: UUID, toSpaceID: UUID?) async throws -> Note {
        var note = try await notes.loadNote(id: id)
        note.spaceID = toSpaceID
        let saved = try await saveNote(note)
        try await log(
            noteID: note.id,
            kind: .noteFiledToSpace,
            message: "Changed the space for note \(note.id.uuidString)."
        )
        return saved
    }

    public func assignNotes(ids: [UUID], toSpaceID: UUID?) async throws {
        for id in ids {
            try await assignNote(id: id, toSpaceID: toSpaceID)
        }
    }

    public func listTasks() async throws -> [TaskItem] {
        try await tasks.list().sorted {
            if $0.isDone != $1.isDone {
                return !$0.isDone
            }
            return StableOrder.ascending($0, $1, by: \.createdAt)
        }
    }

    @discardableResult
    public func setTaskDone(_ taskID: UUID, isDone: Bool) async throws -> TaskItem {
        guard var task = try await tasks.list().first(where: { $0.id == taskID }) else {
            throw VellumError.taskNotFound(taskID)
        }
        guard task.isDone != isDone else { return task }

        task.isDone = isDone
        task.completedAt = isDone ? Date() : nil
        try await tasks.save(task)
        if isDone {
            try await log(
                noteID: task.noteID,
                kind: .taskCompleted,
                message: "Completed task '\(task.text)'."
            )
        }
        return task
    }

    public func activityDigest(since: Date) async throws -> ActivityDigest {
        let events = try await activityRepository.list(noteID: nil)
            .filter { $0.createdAt >= since }
        var counts: [ActivityKind: Int] = [:]
        for event in events {
            counts[event.kind, default: 0] += 1
        }
        let agentActionKinds: Set<ActivityKind> = [
            .proposalAccepted,
            .taskExtracted,
            .entityExtracted,
            .noteFiledToSpace,
            .notesLinked,
            .spaceCreated,
        ]
        let totalAgentActions = counts.reduce(into: 0) { total, entry in
            if agentActionKinds.contains(entry.key) {
                total += entry.value
            }
        }
        return ActivityDigest(
            since: since,
            countsByKind: counts,
            totalAgentActions: totalAgentActions
        )
    }

    public func listNoteSummaries() async throws -> [NoteSummary] {
        var summaries: [NoteSummary] = []
        for note in try await notes.listNotes() {
            let orderedPages = note.pages.sorted(by: NotePage.byOrder)
            let preview = orderedPages
                .map(\.plainText)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasInk: Bool
            if let firstPage = orderedPages.first {
                let size = try await notes.assetSize(
                    noteID: note.id,
                    relativePath: firstPage.drawingAssetPath
                )
                hasInk = (size ?? 0) > 0
            } else {
                hasInk = false
            }
            summaries.append(
                NoteSummary(
                    id: note.id,
                    title: note.title,
                    noteType: note.noteType,
                    spaceID: note.spaceID,
                    previewText: String(preview.prefix(160)),
                    hasInk: hasInk,
                    linkCount: note.links.count,
                    updatedAt: note.updatedAt
                )
            )
        }
        return summaries.sorted { StableOrder.descending($0, $1, by: \.updatedAt) }
    }

    public func requestAnalysis(noteID: UUID) async throws -> [AgentProposal] {
        let note = try await notes.loadNote(id: noteID)
        let canonicalText = note.pages
            .sorted(by: NotePage.byOrder)
            .map(\.plainText)
            .joined(separator: "\n\n")
        let now = Date()
        let event = WorkspaceEvent(
            id: UUID(),
            noteID: note.id,
            noteRevision: note.revision,
            createdAt: now,
            kind: .analysisRequested
        )
        let context = AgentContext(
            noteID: note.id,
            noteRevision: note.revision,
            title: note.title,
            canonicalText: canonicalText,
            currentSpaceID: note.spaceID,
            spaces: try await spaces.list(),
            otherNotes: try await notes.listNotes()
                .filter { $0.id != note.id }
                .map { NoteRef(id: $0.id, title: $0.title) }
        )
        let generated = try await agent.analyze(event: event, context: context)
        for proposal in generated {
            try await proposals.save(proposal)
        }
        try await log(
            noteID: note.id,
            kind: .analysisRequested,
            message: "Requested analysis for revision \(note.revision)."
        )
        return generated
    }

    public func listProposals(noteID: UUID) async throws -> [AgentProposal] {
        let note = try await notes.loadNote(id: noteID)
        var listed = try await proposals.list(noteID: noteID)
        for index in listed.indices
        where listed[index].status == .pending && listed[index].basedOnRevision != note.revision {
            listed[index].status = .stale
            try await proposals.update(listed[index])
            try await log(
                noteID: noteID,
                kind: .proposalMarkedStale,
                message: "Marked proposal \(listed[index].id.uuidString) stale."
            )
        }
        return listed
    }

    @discardableResult
    public func acceptProposal(id: UUID) async throws -> Note {
        var proposal = try await proposals.load(id: id)
        switch proposal.status {
        case .stale:
            throw VellumError.staleProposal(id)
        case .accepted, .rejected:
            return try await notes.loadNote(id: proposal.noteID)
        case .pending:
            break
        }

        var note = try await notes.loadNote(id: proposal.noteID)
        guard note.revision == proposal.basedOnRevision else {
            proposal.status = .stale
            try await proposals.update(proposal)
            try await log(
                noteID: note.id,
                kind: .proposalMarkedStale,
                message: "Marked proposal \(proposal.id.uuidString) stale."
            )
            throw VellumError.staleProposal(id)
        }

        switch proposal.operation {
        case .addTag(let tag):
            if !note.tags.contains(tag) {
                note.tags.append(tag)
            }
            note = try await saveNote(note)
        case .suggestTitle(let title):
            note.title = title
            note = try await saveNote(note)
        case .createSummary(let summary):
            struct Summary: Encodable {
                let summary: String
                let proposalID: UUID
                let createdAt: Date
            }
            let summaryDocument = Summary(
                summary: summary,
                proposalID: proposal.id,
                createdAt: Date()
            )
            let data: Data
            do {
                data = try FilePersistence.encoder().encode(summaryDocument)
            } catch {
                throw VellumError.persistenceFailure("Could not encode the summary: \(error.localizedDescription)")
            }
            try await notes.saveAsset(
                data,
                noteID: note.id,
                relativePath: "derived/summary.json"
            )
        case .fileToSpace(let spaceName, let color):
            let existing = try await spaces.list().first {
                $0.name.caseInsensitiveCompare(spaceName) == .orderedSame
            }
            let spaceID: UUID
            if let existing {
                spaceID = existing.id
            } else {
                // Agent-accepted filing creates spaces through the same entry point a
                // person does, so whatever `createSpace` enforces holds for both.
                spaceID = try await createSpace(name: spaceName, color: color).id
            }
            note.spaceID = spaceID
            note = try await saveNote(note)
            try await log(
                noteID: note.id,
                kind: .noteFiledToSpace,
                message: "Filed note \(note.id.uuidString) to '\(spaceName)'."
            )
        case .linkNotes(let targetNoteID, let kind):
            _ = try await notes.loadNote(id: targetNoteID)
            if !note.links.contains(where: {
                $0.targetNoteID == targetNoteID && $0.kind == kind
            }) {
                note.links.append(
                    NoteLink(id: UUID(), targetNoteID: targetNoteID, kind: kind, createdAt: Date())
                )
                note = try await saveNote(note)
                try await log(
                    noteID: note.id,
                    kind: .notesLinked,
                    message: "Linked note \(note.id.uuidString) to \(targetNoteID.uuidString)."
                )
            }
        case .extractTask(let text, let pageID):
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let existing = try await tasks.list().contains {
                $0.noteID == proposal.noteID
                    && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
            }
            if !existing {
                try await tasks.save(
                    TaskItem(
                        id: UUID(),
                        noteID: proposal.noteID,
                        pageID: pageID,
                        text: text,
                        isDone: false,
                        createdAt: Date(),
                        completedAt: nil
                    )
                )
            }
            try await log(
                noteID: proposal.noteID,
                kind: .taskExtracted,
                message: "Extracted a task from note \(proposal.noteID.uuidString)."
            )
        case .extractEntity(let name, let kind, let pageID, let excerpt):
            let source = EntitySource(noteID: proposal.noteID, pageID: pageID, excerpt: excerpt)
            if var existing = try await entities.list().first(where: {
                $0.kind == kind && $0.name.lowercased() == name.lowercased()
            }) {
                if !existing.sources.contains(source) {
                    existing.sources.append(source)
                    try await entities.save(existing)
                }
            } else {
                try await entities.save(
                    Entity(
                        id: UUID(),
                        name: name,
                        kind: kind,
                        sources: [source],
                        createdAt: Date()
                    )
                )
            }
            try await log(
                noteID: proposal.noteID,
                kind: .entityExtracted,
                message: "Extracted entity '\(name)'."
            )
        }

        proposal.status = .accepted
        try await proposals.update(proposal)
        try await log(
            noteID: note.id,
            kind: .proposalAccepted,
            message: "Accepted proposal \(proposal.id.uuidString)."
        )
        return note
    }

    public func rejectProposal(id: UUID) async throws {
        var proposal = try await proposals.load(id: id)
        switch proposal.status {
        case .stale:
            throw VellumError.staleProposal(id)
        case .accepted, .rejected:
            return
        case .pending:
            proposal.status = .rejected
            try await proposals.update(proposal)
            try await log(
                noteID: proposal.noteID,
                kind: .proposalRejected,
                message: "Rejected proposal \(proposal.id.uuidString)."
            )
        }
    }

    public func activity(noteID: UUID?) async throws -> [ActivityEvent] {
        try await activityRepository.list(noteID: noteID)
    }

    private func trashNote(_ note: Note) async throws {
        var trashedNote = note
        trashedNote.deletedAt = Date()
        try await notes.saveNote(trashedNote)
        try await log(
            noteID: note.id,
            kind: .noteTrashed,
            message: "Moved note \(note.id.uuidString) to Trash."
        )
    }

    private func log(noteID: UUID?, kind: ActivityKind, message: String) async throws {
        try await activityRepository.append(
            ActivityEvent(
                id: UUID(),
                noteID: noteID,
                createdAt: Date(),
                kind: kind,
                message: message
            )
        )
    }

}
