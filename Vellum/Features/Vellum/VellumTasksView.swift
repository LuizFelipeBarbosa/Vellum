import SwiftUI

struct VellumTasksView: View {
    @Bindable var model: VellumAppModel

    var body: some View {
        @Bindable var tasks = model.tasksScreen

        VStack(alignment: .leading, spacing: 0) {
            TasksHeaderView(tasks: tasks)
                .padding(.bottom, 16)

            TasksContentView(
                groups: tasks.groups,
                totalCount: tasks.totalCount
            ) { taskID in
                Task { await tasks.toggle(taskID) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .background(VellumTheme.paper)
        .alert(
            "Vellum",
            isPresented: Binding(
                get: { tasks.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { tasks.errorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                tasks.errorMessage = nil
            }
        } message: {
            Text(tasks.errorMessage ?? "An unknown error occurred.")
        }
        .task { await tasks.refresh() }
    }
}

private struct TasksHeaderView: View {
    @Bindable var tasks: TasksScreenModel

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tasks")
                    .font(.vellumSans(42, weight: .medium))
                    .foregroundStyle(VellumTheme.ink)
                Text("\(tasks.openCount) open · pulled out of your notes")
                    .font(.vellumCaveat(21))
                    .foregroundStyle(VellumTheme.muted)
            }

            Spacer(minLength: 20)

            Button(tasks.showDone ? "hiding nothing" : "hiding what's done") {
                tasks.showDone.toggle()
            }
            .buttonStyle(TasksDoneToggleButtonStyle(isShowingDone: tasks.showDone))
            .accessibilityLabel(tasks.showDone ? "Hide completed tasks" : "Show completed tasks")
        }
    }
}

private struct TasksContentView: View {
    let groups: [TaskGroupData]
    let totalCount: Int
    let toggle: (UUID) -> Void

    var body: some View {
        ScrollView {
            Group {
                if totalCount == 0 {
                    TasksEmptyState(
                        title: "nothing pulled out yet",
                        subtitle: "tasks appear here when Vellum spots them in your notes"
                    )
                } else if groups.isEmpty {
                    TasksEmptyState(
                        title: "everything's done",
                        subtitle: "nice — nothing left open"
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(groups) { group in
                            TaskGroupView(group: group, toggle: toggle)
                        }
                    }
                    .padding(.bottom, 26)
                }
            }
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

private struct TaskGroupView: View {
    let group: TaskGroupData
    let toggle: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                VellumBlobDot(color: group.color, size: 11)
                Text(group.name)
                    .font(.vellumCaveat(26))
                    .foregroundStyle(VellumTheme.ink)
                    .lineLimit(1)
                VellumDashedRule()
                    .stroke(
                        VellumTheme.ink(0.22),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
                    )
                    .frame(height: 1.5)
            }

            VStack(spacing: 8) {
                ForEach(group.tasks) { row in
                    TaskRowView(row: row, toggle: toggle)
                }
            }
        }
    }
}

private struct TaskRowView: View {
    let row: TaskRowData
    let toggle: (UUID) -> Void

    var body: some View {
        Button {
            toggle(row.id)
        } label: {
            HStack(spacing: 14) {
                TaskCheckbox(isDone: row.isDone)

                VStack(alignment: .leading, spacing: 5) {
                    Text(row.text)
                        .font(.vellumSans(18))
                        .foregroundStyle(row.isDone ? VellumTheme.mutedCount : VellumTheme.ink)
                        .strikethrough(row.isDone)
                        .multilineTextAlignment(.leading)
                    Text("from \(row.noteTitle)")
                        .font(.vellumMono(11))
                        .foregroundStyle(VellumTheme.muted)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TaskRowButtonStyle(isDone: row.isDone))
        .accessibilityLabel(row.text)
        .accessibilityValue(row.isDone ? "Completed, from \(row.noteTitle)" : "Open, from \(row.noteTitle)")
        .accessibilityHint(row.isDone ? "Marks this task as open" : "Marks this task as completed")
    }
}

private struct TaskCheckbox: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let isDone: Bool

    var body: some View {
        let shape = VellumOrganicRectangle(
            topLeading: 10,
            bottomLeading: 4,
            bottomTrailing: 11,
            topTrailing: 5,
            straightRadius: 6,
            isOrganic: vellumWobble
        )

        ZStack {
            shape.strokeBorder(VellumTheme.ink, lineWidth: 2)
            if isDone {
                Text("✓")
                    .font(.vellumCaveat(26))
                    .foregroundStyle(VellumTheme.accent)
                    .offset(y: -1)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

private struct TasksEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.vellumSans(24, italic: true))
                .foregroundStyle(VellumTheme.bodyMuted)
            Text(subtitle)
                .font(.vellumCaveat(18))
                .foregroundStyle(VellumTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}

private struct TasksDoneToggleButtonStyle: ButtonStyle {
    @Environment(\.vellumWobble) private var vellumWobble

    let isShowingDone: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = OrganicPillShape(variant: 1, isOrganic: vellumWobble)

        configuration.label
            .font(.vellumSans(16.5))
            .foregroundStyle(VellumTheme.mutedDark)
            .lineLimit(1)
            .padding(.horizontal, 20)
            .frame(minHeight: 46)
            .background(isShowingDone ? Color.clear : VellumTheme.ink(0.06), in: shape)
            .overlay {
                shape.strokeBorder(VellumTheme.ink(0.3), lineWidth: 1.5)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct TaskRowButtonStyle: ButtonStyle {
    @Environment(\.vellumWobble) private var vellumWobble

    let isDone: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = VellumOrganicRectangle(
            topLeading: 20,
            bottomLeading: 8,
            bottomTrailing: 22,
            topTrailing: 8,
            straightRadius: 14,
            isOrganic: vellumWobble
        )

        configuration.label
            .background(isDone ? VellumTheme.stripeCard : VellumTheme.card, in: shape)
            .background {
                if !isDone {
                    shape
                        .fill(VellumTheme.ink(0.1))
                        .offset(x: 3, y: 4)
                }
            }
            .overlay {
                shape.strokeBorder(VellumTheme.ink(0.26), lineWidth: 1.5)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
