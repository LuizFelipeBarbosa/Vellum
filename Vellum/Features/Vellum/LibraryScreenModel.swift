import Foundation
import Observation
import SwiftUI
import VellumCore

enum LibraryCardTreatment {
    case handwritten
    case stripe(label: String)
    case audio
}

enum LibraryDisplayMode: String {
    case pinboard
    case fieldGuide
}

struct LibraryCardData: Identifiable {
    let id: UUID
    let title: String
    let previewText: String
    let treatment: LibraryCardTreatment
    let metaLine: String
    let dotColor: Color
    let spaceID: UUID?
}

struct LibraryCardGroup: Identifiable {
    let id: String
    let name: String
    let color: Color
    let cards: [LibraryCardData]
    let cardCount: Int
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
    var unsupportedNoteCount = 0
    var filter: NoteType?
    var selectedSpaceID: UUID?
    var displayMode: LibraryDisplayMode {
        didSet {
            UserDefaults.standard.set(
                displayMode.rawValue,
                forKey: "vellum.libraryDisplayMode"
            )
        }
    }
    var isLoading = false
    var errorMessage: String?
    var isSelecting = false
    var selectedIDs: Set<UUID> = []
    var isConfirmingBulkDelete = false

    var renamingNoteID: UUID?
    var renameDraft = ""
    var notePendingDeletionID: UUID?

    init(workspace: WorkspaceService) {
        self.workspace = workspace
        displayMode = LibraryDisplayMode(
            rawValue: UserDefaults.standard.string(
                forKey: "vellum.libraryDisplayMode"
            ) ?? ""
        ) ?? .pinboard
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let refreshedSummaries = try await workspace.listNoteSummaries()
            let refreshedSpaces = try await workspace.listSpaces()
            let unsupportedNotes = try await workspace.unsupportedNotes()
            summaries = refreshedSummaries
            spaces = refreshedSpaces
            unsupportedNoteCount = unsupportedNotes.count
            if let selectedSpaceID,
               !refreshedSpaces.contains(where: { $0.space.id == selectedSpaceID }) {
                self.selectedSpaceID = nil
            }
            selectedIDs = selectedIDs.intersection(Set(summaries.map(\.id)))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var cards: [LibraryCardData] {
        let spacesByID = self.spacesByID
        let allowedSpaceIDs: Set<UUID>? = selectedSpaceID.map { selected in
            Set([selected] + spaces.filter { $0.space.parentID == selected }.map(\.space.id))
        }

        return summaries.compactMap { summary in
            guard filter == nil || summary.noteType == filter else { return nil }
            if let allowedSpaceIDs {
                guard let spaceID = summary.spaceID,
                      allowedSpaceIDs.contains(spaceID) else { return nil }
            }

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
                dotColor: space.map { VellumTheme.color(for: $0.color) }
                    ?? VellumTheme.color(for: .gray),
                spaceID: space?.id
            )
        }
    }

    var cardGroups: [LibraryCardGroup] {
        let spacesByID = self.spacesByID
        var cardsBySpaceID: [UUID: [LibraryCardData]] = [:]
        var orderedSpaceIDs: [UUID] = []
        var unfiledCards: [LibraryCardData] = []

        for card in cards {
            guard let spaceID = card.spaceID,
                  spacesByID[spaceID] != nil else {
                unfiledCards.append(card)
                continue
            }
            if cardsBySpaceID[spaceID] == nil {
                orderedSpaceIDs.append(spaceID)
            }
            cardsBySpaceID[spaceID, default: []].append(card)
        }

        var groups = orderedSpaceIDs.compactMap { spaceID -> LibraryCardGroup? in
            guard let space = spacesByID[spaceID],
                  let cards = cardsBySpaceID[spaceID],
                  !cards.isEmpty else { return nil }
            return LibraryCardGroup(
                id: spaceID.uuidString,
                name: space.name,
                color: VellumTheme.color(for: space.color),
                cards: cards,
                cardCount: cards.count
            )
        }

        if !unfiledCards.isEmpty {
            groups.append(
                LibraryCardGroup(
                    id: "unfiled",
                    name: "Unfiled",
                    color: VellumTheme.color(for: .gray),
                    cards: unfiledCards,
                    cardCount: unfiledCards.count
                )
            )
        }
        return groups
    }

    var libraryTitle: String {
        guard let selectedSpaceID,
              let space = spacesByID[selectedSpaceID] else { return "Library" }
        return space.name
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

    func createNoteFromPDF(data: Data, suggestedTitle: String) async -> UUID? {
        let importResult: (note: Note, assetRelativePath: String)
        do {
            importResult = try PDFImportService.buildNote(
                fromPDFData: data,
                title: suggestedTitle
            )
        } catch let error as PDFImportError {
            switch error {
            case .unreadable:
                errorMessage = "The selected file could not be read as a PDF."
            case .encrypted:
                errorMessage = "Encrypted PDFs are not supported."
            case .empty:
                errorMessage = "The selected PDF has no pages."
            case .tooManyPages:
                errorMessage = "PDFs can contain at most \(PDFImportService.maxPageCount) pages."
            }
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        do {
            try await workspace.importNote(
                importResult.note,
                assets: [
                    (
                        relativePath: importResult.assetRelativePath,
                        data: data
                    )
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        await refresh()
        return importResult.note.id
    }

    func beginSelecting() {
        isSelecting = true
    }

    func endSelecting() {
        isSelecting = false
        selectedIDs = []
        isConfirmingBulkDelete = false
    }

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func moveSelected(toSpaceID spaceID: UUID?) async {
        do {
            try await workspace.assignNotes(ids: Array(selectedIDs), toSpaceID: spaceID)
            await refresh()
            endSelecting()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelected() async -> [UUID] {
        let ids = Array(selectedIDs)

        do {
            let trashedIDs = try await workspace.deleteNotes(ids: ids)
            await refresh()
            endSelecting()
            return trashedIDs
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func beginRename(_ summary: LibraryCardData) {
        renamingNoteID = summary.id
        renameDraft = summary.title
    }

    func cancelRename() {
        renamingNoteID = nil
    }

    func commitRename(noteID: UUID) async {
        let newTitle = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingNoteID = nil

        do {
            var note = try await workspace.loadNote(id: noteID)
            note.title = newTitle.isEmpty ? "Untitled" : newTitle
            note.titleOrigin = .manual
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

    func confirmDelete(_ noteID: UUID) async -> UUID? {
        notePendingDeletionID = nil

        do {
            try await workspace.deleteNote(id: noteID)
            await refresh()
            return noteID
        } catch {
            errorMessage = error.localizedDescription
            return nil
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

    private var spacesByID: [UUID: Space] {
        Dictionary(uniqueKeysWithValues: spaces.map { ($0.space.id, $0.space) })
    }
}
