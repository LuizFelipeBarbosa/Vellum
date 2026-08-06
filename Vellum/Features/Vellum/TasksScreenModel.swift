import Foundation
import Observation
import SwiftUI
import VellumCore

struct TaskRowData: Identifiable {
    let id: UUID
    let text: String
    let isDone: Bool
    let noteTitle: String
}

struct TaskGroupData: Identifiable {
    let id: String
    let name: String
    let color: Color
    let tasks: [TaskRowData]
}

@MainActor
@Observable
final class TasksScreenModel {
    private let container: AppContainer
    private var taskItems: [TaskItem] = []
    private var noteSummaries: [NoteSummary] = []
    private var spaceListings: [SpaceListing] = []
    private var pendingToggleIDs: Set<UUID> = []

    private(set) var groups: [TaskGroupData] = []
    private(set) var openCount = 0
    private(set) var totalCount = 0
    var errorMessage: String?
    var showDone: Bool {
        didSet {
            UserDefaults.standard.set(showDone, forKey: "vellum.tasks.showDone")
            rebuildGroups()
        }
    }

    init(container: AppContainer) {
        self.container = container
        if UserDefaults.standard.object(forKey: "vellum.tasks.showDone") == nil {
            showDone = true
        } else {
            showDone = UserDefaults.standard.bool(forKey: "vellum.tasks.showDone")
        }
    }

    func refresh() async {
        do {
            let refreshedTasks = try await container.workspace.listTasks()
            let refreshedSummaries = try await container.workspace.listNoteSummaries()
            let refreshedSpaces = try await container.workspace.listSpaces()

            taskItems = refreshedTasks
            noteSummaries = refreshedSummaries
            spaceListings = refreshedSpaces
            rebuildGroups()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ taskID: UUID) async {
        guard !pendingToggleIDs.contains(taskID),
              let taskIndex = taskItems.firstIndex(where: { $0.id == taskID }) else {
            return
        }

        pendingToggleIDs.insert(taskID)
        defer { pendingToggleIDs.remove(taskID) }

        let previousTask = taskItems[taskIndex]
        var optimisticTask = previousTask
        optimisticTask.isDone.toggle()
        optimisticTask.completedAt = optimisticTask.isDone ? Date() : nil
        taskItems[taskIndex] = optimisticTask
        rebuildGroups()

        do {
            let savedTask = try await container.workspace.setTaskDone(
                taskID,
                isDone: optimisticTask.isDone
            )
            if let savedIndex = taskItems.firstIndex(where: { $0.id == taskID }) {
                taskItems[savedIndex] = savedTask
            }
            rebuildGroups()
            errorMessage = nil
        } catch {
            let toggleErrorMessage = error.localizedDescription
            if let rollbackIndex = taskItems.firstIndex(where: { $0.id == taskID }) {
                taskItems[rollbackIndex] = previousTask
                rebuildGroups()
            }
            await refresh()
            errorMessage = toggleErrorMessage
        }
    }

    private func rebuildGroups() {
        totalCount = taskItems.count
        openCount = taskItems.count { !$0.isDone }

        var notesByID: [UUID: NoteSummary] = [:]
        for summary in noteSummaries {
            notesByID[summary.id] = summary
        }

        var spacesByID: [UUID: SpaceListing] = [:]
        for listing in spaceListings {
            spacesByID[listing.space.id] = listing
        }

        let visibleTasks = showDone ? taskItems : taskItems.filter { !$0.isDone }
        var tasksBySpaceID: [UUID: [TaskItem]] = [:]
        var unfiledTasks: [TaskItem] = []

        for task in visibleTasks {
            guard let note = notesByID[task.noteID],
                  let spaceID = note.spaceID,
                  spacesByID[spaceID] != nil else {
                unfiledTasks.append(task)
                continue
            }
            tasksBySpaceID[spaceID, default: []].append(task)
        }

        var rebuiltGroups = tasksBySpaceID.compactMap { spaceID, tasks -> TaskGroupData? in
            guard let listing = spacesByID[spaceID] else { return nil }
            return TaskGroupData(
                id: spaceID.uuidString,
                name: listing.space.name,
                color: VellumTheme.color(for: listing.space.color),
                tasks: rows(from: tasks, notesByID: notesByID)
            )
        }
        rebuiltGroups.sort { lhs, rhs in
            let nameOrder = lhs.name.caseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.id < rhs.id
        }

        if !unfiledTasks.isEmpty {
            rebuiltGroups.append(
                TaskGroupData(
                    id: "unfiled",
                    name: "Unfiled",
                    color: VellumTheme.muted,
                    tasks: rows(from: unfiledTasks, notesByID: notesByID)
                )
            )
        }
        groups = rebuiltGroups
    }

    private func rows(
        from tasks: [TaskItem],
        notesByID: [UUID: NoteSummary]
    ) -> [TaskRowData] {
        tasks.sorted(by: taskComesBefore).map { task in
            let noteTitle = notesByID[task.noteID]?.title ?? ""
            return TaskRowData(
                id: task.id,
                text: task.text,
                isDone: task.isDone,
                noteTitle: noteTitle.isEmpty ? "Untitled" : noteTitle
            )
        }
    }

    private func taskComesBefore(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.isDone != rhs.isDone {
            return !lhs.isDone
        }

        let lhsDate = lhs.isDone ? lhs.completedAt ?? lhs.createdAt : lhs.createdAt
        let rhsDate = rhs.isDone ? rhs.completedAt ?? rhs.createdAt : rhs.createdAt
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
