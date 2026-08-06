import Foundation
import VellumCore

/// Applies text recognition results to an open note editor's model.
@MainActor
protocol RecognitionApplying: AnyObject {
    func currentRecognitionInput() -> TextRecognitionInput?
    func applyRecognitionOutcome(_ outcome: TextRecognitionOutcome)
}

@MainActor
final class NoteTextRecognitionCoordinator {
    private final class WeakApplierBox {
        weak var applier: (any RecognitionApplying)?

        init(_ applier: any RecognitionApplying) {
            self.applier = applier
        }
    }

    private let service: TextRecognitionService
    private let workspace: WorkspaceService
    private let notes: any NoteRepository
    private let debounce: Duration

    private var appliers: [UUID: WeakApplierBox] = [:]
    private var lastFingerprint: [UUID: String] = [:]
    private var seededNoteIDs: Set<UUID> = []
    private var pendingSeedInputs: [UUID: (TextRecognitionInput, String)] = [:]
    private var seedTasks: [UUID: Task<Void, Never>] = [:]
    private var recognitionTasks: [UUID: Task<Void, Never>] = [:]
    private var recognitionTaskIDs: [UUID: UUID] = [:]

    init(
        service: TextRecognitionService,
        workspace: WorkspaceService,
        notes: any NoteRepository,
        debounce: Duration = .seconds(2)
    ) {
        self.service = service
        self.workspace = workspace
        self.notes = notes
        self.debounce = debounce
    }

    func register(_ applier: any RecognitionApplying, noteID: UUID) {
        appliers[noteID] = WeakApplierBox(applier)
    }

    func unregister(noteID: UUID) {
        appliers[noteID] = nil
    }

    func noteDidSave(_ input: TextRecognitionInput) {
        let noteID = input.noteID
        let fingerprint = TextRecognitionService.fingerprint(for: input)
        guard !seededNoteIDs.contains(noteID) else {
            enqueueRecognition(for: input, fingerprint: fingerprint)
            return
        }

        pendingSeedInputs[noteID] = (input, fingerprint)
        guard seedTasks[noteID] == nil else { return }

        seedTasks[noteID] = Task { [weak self] in
            guard let self else { return }

            let fingerprint: String?
            do {
                if let data = try await notes.loadAsset(
                    noteID: noteID,
                    relativePath: RecognitionSidecar.relativePath
                ) {
                    let recognizedText = try VellumJSONCoding.decoder()
                        .decode(RecognizedNoteText.self, from: data)
                    let sidecarPageTexts = Dictionary(
                        uniqueKeysWithValues: recognizedText.pages.map { ($0.pageID, $0.plainText) }
                    )
                    let pendingPageTexts = Dictionary(
                        uniqueKeysWithValues: pendingSeedInputs[noteID]?.0.pages.map {
                            ($0.id, $0.plainText)
                        } ?? []
                    )
                    let pageIDs = Set(sidecarPageTexts.keys).union(pendingPageTexts.keys)
                    // The sidecar can land before an open editor's scheduled autosave, so
                    // skip seeding stale page text after a crash and let recognition self-heal.
                    let pageTextsMatch = pageIDs.allSatisfy {
                        sidecarPageTexts[$0, default: ""] == pendingPageTexts[$0, default: ""]
                    }
                    fingerprint = pageTextsMatch ? recognizedText.inputFingerprint : nil
                } else {
                    fingerprint = nil
                }
            } catch {
                fingerprint = nil
            }

            finishSeeding(noteID: noteID, fingerprint: fingerprint)
        }
    }

    private func finishSeeding(noteID: UUID, fingerprint: String?) {
        seedTasks[noteID] = nil
        seededNoteIDs.insert(noteID)
        if let fingerprint {
            lastFingerprint[noteID] = fingerprint
        }

        guard let pending = pendingSeedInputs.removeValue(forKey: noteID) else { return }
        enqueueRecognition(for: pending.0, fingerprint: pending.1)
    }

    private func enqueueRecognition(
        for input: TextRecognitionInput,
        fingerprint: String
    ) {
        guard lastFingerprint[input.noteID] != fingerprint else { return }

        recognitionTasks[input.noteID]?.cancel()
        let taskID = UUID()
        recognitionTaskIDs[input.noteID] = taskID
        recognitionTasks[input.noteID] = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: debounce)
                try Task.checkCancellation()
                let outcome = try await service.recognize(input)
                try Task.checkCancellation()
                try await apply(outcome)
            } catch is CancellationError {
                // Superseded recognition is expected during normal editing.
            } catch {
                print("WARNING: text recognition failed: \(error)")
            }

            finishRecognitionTask(noteID: input.noteID, taskID: taskID)
        }
    }

    private func apply(_ outcome: TextRecognitionOutcome) async throws {
        if let applier = registeredApplier(for: outcome.noteID) {
            guard apply(outcome, to: applier) else { return }
        } else {
            guard try await applyToClosedNote(outcome) else { return }
        }

        let data = try VellumJSONCoding.encoder().encode(outcome.document)
        try await notes.saveAsset(
            data,
            noteID: outcome.noteID,
            relativePath: RecognitionSidecar.relativePath
        )
        lastFingerprint[outcome.noteID] = outcome.fingerprint
    }

    private func apply(
        _ outcome: TextRecognitionOutcome,
        to applier: any RecognitionApplying
    ) -> Bool {
        guard let currentInput = applier.currentRecognitionInput(),
              TextRecognitionService.fingerprint(for: currentInput) == outcome.fingerprint else {
            return false
        }

        applier.applyRecognitionOutcome(outcome)
        return true
    }

    private func applyToClosedNote(_ outcome: TextRecognitionOutcome) async throws -> Bool {
        let freshNote = try await workspace.loadNote(id: outcome.noteID)
        let orderedPages = Self.orderedPages(freshNote.pages)
        let freshDrawingData: Data?
        if let drawingAssetPath = orderedPages.first?.drawingAssetPath {
            freshDrawingData = try await notes.loadAsset(
                noteID: outcome.noteID,
                relativePath: drawingAssetPath
            )
        } else {
            freshDrawingData = nil
        }

        try Task.checkCancellation()
        let recomputedInput = TextRecognitionInput(
            note: freshNote,
            drawingData: freshDrawingData
        )
        guard TextRecognitionService.fingerprint(for: recomputedInput) == outcome.fingerprint else {
            return false
        }

        // A note may have opened while its persisted state was being reloaded.
        if let applier = registeredApplier(for: outcome.noteID) {
            return apply(outcome, to: applier)
        }

        let shouldAutoTitle = freshNote.isEligibleForAutoTitle
        var mutatedNote = freshNote
        var didChange = false

        for index in mutatedNote.pages.indices {
            let pageID = mutatedNote.pages[index].id
            guard let text = outcome.pageTexts[pageID],
                  text != mutatedNote.pages[index].plainText else {
                continue
            }
            mutatedNote.pages[index].plainText = text
            didChange = true
        }

        if shouldAutoTitle,
           let pageText = orderedPages.lazy.compactMap({ page -> String? in
               guard let text = outcome.pageTexts[page.id],
                     !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                   return nil
               }
               return text
           }).first {
            let title = TitleSuggestion.firstSentence(from: pageText)
            if !title.isEmpty,
               (mutatedNote.title != title || mutatedNote.titleOrigin != .auto) {
                mutatedNote.title = title
                mutatedNote.titleOrigin = .auto
                didChange = true
            }
        }

        if didChange {
            try Task.checkCancellation()
            try await workspace.saveNote(mutatedNote)
        }
        return true
    }

    private func registeredApplier(for noteID: UUID) -> (any RecognitionApplying)? {
        guard let box = appliers[noteID] else { return nil }
        guard let applier = box.applier else {
            appliers[noteID] = nil
            return nil
        }
        return applier
    }

    private func finishRecognitionTask(noteID: UUID, taskID: UUID) {
        guard recognitionTaskIDs[noteID] == taskID else { return }
        recognitionTaskIDs[noteID] = nil
        recognitionTasks[noteID] = nil
    }

    private static func orderedPages(_ pages: [NotePage]) -> [NotePage] {
        pages.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.order < rhs.order
        }
    }
}
