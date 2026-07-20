import Foundation
import Observation
import VellumCore

struct TrashRow: Identifiable {
    let id: UUID
    let title: String
    let deletedAt: Date
    let spaceName: String?
}

@MainActor
@Observable
final class TrashScreenModel {
    private let workspace: WorkspaceService

    var rows: [TrashRow] = []
    var errorMessage: String?
    var pendingPurgeID: UUID?
    var isConfirmingEmptyTrash = false

    init(workspace: WorkspaceService) {
        self.workspace = workspace
    }

    func refresh() async {
        do {
            let notes = try await workspace.listTrashedNotes()
            let spaces = try await workspace.listSpaces()
            let spacesByID = Dictionary(uniqueKeysWithValues: spaces.map { ($0.space.id, $0.space) })
            rows = notes.map { note in
                TrashRow(
                    id: note.id,
                    title: note.title.isEmpty ? "Untitled" : note.title,
                    deletedAt: note.deletedAt ?? Date(),
                    spaceName: note.spaceID.flatMap { spacesByID[$0]?.name }
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore(_ id: UUID) async {
        do {
            _ = try await workspace.restoreNote(id: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestPurge(_ id: UUID) {
        pendingPurgeID = id
    }

    func cancelPurge() {
        pendingPurgeID = nil
    }

    func confirmPurge(_ id: UUID) async {
        pendingPurgeID = nil
        do {
            try await workspace.purgeNote(id: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func emptyTrash() async {
        do {
            try await workspace.emptyTrash()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
