import Foundation
import Observation
import SwiftUI
import VellumCore

enum LibraryCardTreatment {
    case handwritten
    case stripe(label: String)
    case audio
}

struct LibraryCardData: Identifiable {
    let id: UUID
    let title: String
    let previewText: String
    let treatment: LibraryCardTreatment
    let metaLine: String
    let dotColor: Color
}

extension NoteType {
    var libraryFilterLabel: String {
        switch self {
        case .note: "Notes"
        case .pdf: "PDFs"
        case .deck: "Decks"
        case .image: "Images"
        case .audio: "Audio"
        }
    }
}

@MainActor
@Observable
final class LibraryScreenModel {
    private let workspace: WorkspaceService

    var summaries: [NoteSummary] = []
    var spaces: [SpaceListing] = []
    var filter: NoteType?
    var selectedSpaceID: UUID?
    var isLoading = false
    var errorMessage: String?

    var renamingNoteID: UUID?
    var renameDraft = ""
    var notePendingDeletionID: UUID?

    init(workspace: WorkspaceService) {
        self.workspace = workspace
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let refreshedSummaries = try await workspace.listNoteSummaries()
            let refreshedSpaces = try await workspace.listSpaces()
            summaries = refreshedSummaries
            spaces = refreshedSpaces
            if let selectedSpaceID,
               !refreshedSpaces.contains(where: { $0.space.id == selectedSpaceID }) {
                self.selectedSpaceID = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var cards: [LibraryCardData] {
        let spacesByID = Dictionary(uniqueKeysWithValues: spaces.map { ($0.space.id, $0.space) })

        return summaries.compactMap { summary in
            guard filter == nil || summary.noteType == filter else { return nil }
            guard selectedSpaceID == nil || summary.spaceID == selectedSpaceID else { return nil }

            let treatment = treatment(for: summary)
            let descriptor = descriptor(for: treatment, summary: summary)
            let space = summary.spaceID.flatMap { spacesByID[$0] }
            var metaParts: [String] = []
            if let space {
                metaParts.append(space.name)
            }
            metaParts.append(descriptor)
            if summary.linkCount > 0 {
                metaParts.append("\(summary.linkCount) \(summary.linkCount == 1 ? "link" : "links")")
            }
            metaParts.append(relativeTime(for: summary.updatedAt))

            let previewText: String
            if case .audio = treatment {
                previewText = summary.previewText.isEmpty ? "audio" : "audio · transcribed"
            } else {
                previewText = summary.previewText
            }

            return LibraryCardData(
                id: summary.id,
                title: summary.title.isEmpty ? "Untitled" : summary.title,
                previewText: previewText,
                treatment: treatment,
                metaLine: metaParts.joined(separator: " · "),
                dotColor: space.map { VellumTheme.color(for: $0.color) } ?? VellumTheme.color(for: .gray)
            )
        }
    }

    var countLine: String {
        var filters: [String] = []
        if let filter {
            filters.append(filter.libraryFilterLabel)
        }
        if let selectedSpaceID,
           let spaceName = spaces.first(where: { $0.space.id == selectedSpaceID })?.space.name {
            filters.append(spaceName)
        }

        guard !filters.isEmpty else {
            return "\(summaries.count) \(summaries.count == 1 ? "source" : "sources")"
        }
        return "\(cards.count) shown · filtered to \(filters.joined(separator: " + "))"
    }

    func createNote() async -> UUID? {
        do {
            let note = try await workspace.createNote(title: "Untitled")
            await refresh()
            return note.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func beginRename(_ summary: LibraryCardData) {
        renamingNoteID = summary.id
        renameDraft = summary.title
    }

    func cancelRename() {
        renamingNoteID = nil
        renameDraft = ""
    }

    func commitRename() async {
        guard let noteID = renamingNoteID else { return }
        let newTitle = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRename()

        do {
            var note = try await workspace.loadNote(id: noteID)
            note.title = newTitle.isEmpty ? "Untitled" : newTitle
            _ = try await workspace.saveNote(note)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestDelete(_ id: UUID) {
        notePendingDeletionID = id
    }

    func cancelDelete() {
        notePendingDeletionID = nil
    }

    func confirmDelete() async {
        guard let noteID = notePendingDeletionID else { return }
        notePendingDeletionID = nil

        do {
            try await workspace.deleteNote(id: noteID)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func treatment(for summary: NoteSummary) -> LibraryCardTreatment {
        if summary.hasInk {
            return .handwritten
        }

        return switch summary.noteType {
        case .note: .stripe(label: "note · typed")
        case .pdf: .stripe(label: "PDF · first page preview")
        case .deck: .stripe(label: "deck · slides")
        case .image: .stripe(label: "photo · capture")
        case .audio: .audio
        }
    }

    private func descriptor(for treatment: LibraryCardTreatment, summary: NoteSummary) -> String {
        switch treatment {
        case .handwritten:
            "handwritten"
        case .stripe(let label):
            label
        case .audio:
            summary.previewText.isEmpty ? "audio" : "audio · transcribed"
        }
    }

    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
