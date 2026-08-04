import Foundation
import Observation
import VellumCore

struct TodayRecentNote: Identifiable {
    let id: UUID
    let title: String
    let previewText: String
    let noteType: NoteType
    let spaceID: UUID?
    let relativeTime: String
}

struct TodayLooseThread: Identifiable {
    let id: UUID
    let name: String
    let kind: EntityKind
    let sourceCount: Int
}

struct TodayOpenTask: Identifiable {
    let id: UUID
    let noteID: UUID
    let text: String
    let isDone: Bool
    let sourceNoteTitle: String
}

struct TodayNoteExcerpt: Identifiable {
    let id: UUID
    let title: String
    let previewText: String
}

@MainActor
@Observable
final class TodayScreenModel {
    private let container: AppContainer
    private var noteTitlesByID: [UUID: String] = [:]
    private var workspaceNoteCount = 0

    private(set) var digestSubline: String?
    private(set) var recentNotes: [TodayRecentNote] = []
    private(set) var looseThreads: [TodayLooseThread] = []
    private(set) var openTasks: [TodayOpenTask] = []
    private(set) var totalOpenTaskCount = 0
    private(set) var fromYourNotes: TodayNoteExcerpt?
    private(set) var hasLoadedNotes = false
    private(set) var hasLoadedTasks = false

    init(container: AppContainer) {
        self.container = container
    }

    var dateLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE '·' d MMMM"
        return formatter.string(from: .now).uppercased()
    }

    var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<12: "Good morning."
        case 12..<18: "Good afternoon."
        default: "Good evening."
        }
    }

    var isWorkspaceEmpty: Bool {
        hasLoadedNotes && workspaceNoteCount == 0
    }

    func refresh() async {
        let now = Date.now

        async let summariesResult = try? container.workspace.listNoteSummaries()
        async let tasksResult = try? container.workspace.listTasks()
        async let entitiesResult = try? container.entities.list()
        async let digestResult = try? container.workspace.activityDigest(
            since: now.addingTimeInterval(-24 * 3600)
        )

        if let summaries = await summariesResult {
            updateNotes(summaries, relativeTo: now)
        }

        if let tasks = await tasksResult {
            updateTasks(tasks)
        }

        if let entities = await entitiesResult {
            looseThreads = entities.sorted(by: entityPrecedes).prefix(6).map { entity in
                TodayLooseThread(
                    id: entity.id,
                    name: entity.name,
                    kind: entity.kind,
                    sourceCount: entity.sources.count
                )
            }
        }

        if let digest = await digestResult {
            digestSubline = digestLine(for: digest.totalAgentActions)
        }
    }

    func toggleTask(id: UUID, isDone: Bool) async {
        _ = try? await container.workspace.setTaskDone(id, isDone: isDone)
        await refresh()
    }

    private func updateNotes(_ summaries: [NoteSummary], relativeTo now: Date) {
        let sortedSummaries = summaries.sorted(by: notePrecedes)
        let displayedSummaries = Array(sortedSummaries.prefix(3))

        workspaceNoteCount = summaries.count
        hasLoadedNotes = true
        noteTitlesByID = Dictionary(
            summaries.map { ($0.id, displayTitle($0.title)) },
            uniquingKeysWith: { first, _ in first }
        )
        recentNotes = displayedSummaries.map { summary in
            TodayRecentNote(
                id: summary.id,
                title: displayTitle(summary.title),
                previewText: summary.previewText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                noteType: summary.noteType,
                spaceID: summary.spaceID,
                relativeTime: relativeTime(for: summary.updatedAt, relativeTo: now)
            )
        }

        let recentIDs = Set(displayedSummaries.map(\.id))
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let excerptSummary = summaries
            .filter {
                !recentIDs.contains($0.id)
                    && $0.updatedAt >= sevenDaysAgo
                    && $0.updatedAt <= now
            }
            .min(by: noteIsOlder)

        fromYourNotes = excerptSummary.map { summary in
            TodayNoteExcerpt(
                id: summary.id,
                title: displayTitle(summary.title),
                previewText: summary.previewText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        }
    }

    private func updateTasks(_ tasks: [TaskItem]) {
        let allOpenTasks = tasks.filter { !$0.isDone }
        totalOpenTaskCount = allOpenTasks.count
        hasLoadedTasks = true
        openTasks = allOpenTasks.prefix(3).map { task in
            TodayOpenTask(
                id: task.id,
                noteID: task.noteID,
                text: task.text,
                isDone: task.isDone,
                sourceNoteTitle: noteTitlesByID[task.noteID] ?? "Untitled"
            )
        }
    }

    private func notePrecedes(_ lhs: NoteSummary, _ rhs: NoteSummary) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func noteIsOlder(_ lhs: NoteSummary, _ rhs: NoteSummary) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func entityPrecedes(_ lhs: Entity, _ rhs: Entity) -> Bool {
        if lhs.sources.count != rhs.sources.count {
            return lhs.sources.count > rhs.sources.count
        }
        let nameOrder = lhs.name.caseInsensitiveCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func relativeTime(for date: Date, relativeTo now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private func displayTitle(_ title: String) -> String {
        title.isEmpty ? "Untitled" : title
    }

    private func digestLine(for actionCount: Int) -> String {
        switch actionCount {
        case 0: "all quiet since yesterday"
        case 1: "one thing happened while you were away"
        default: "\(actionCount) things happened while you were away"
        }
    }
}
