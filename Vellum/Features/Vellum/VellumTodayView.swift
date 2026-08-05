import SwiftUI
import VellumCore

struct VellumTodayView: View {
    @Bindable var model: VellumAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TodayHeader(model: model.today)
                    .padding(.bottom, 26)

                if model.today.isWorkspaceEmpty {
                    emptyState
                } else {
                    TodayTwoColumnLayout(ratio: 1.15, spacing: 22) {
                        TodayLeftColumn(model: model)
                        TodayRightColumn(model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .background(VellumTheme.paper)
        .alert(
            "Vellum",
            isPresented: Binding(
                get: { model.today.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { model.today.errorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.today.errorMessage = nil
            }
        } message: {
            Text(model.today.errorMessage ?? "An unknown error occurred.")
        }
        .task { await model.today.refresh() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("There are no notes yet.")
                .font(.vellumCaveat(24))
                .foregroundStyle(VellumTheme.mutedDark)

            Button {
                Task {
                    if let id = await model.library.createNote() {
                        await model.openNote(id, isNewlyCreated: true)
                    }
                }
            } label: {
                Text("New note")
                    .font(.vellumSans(17, weight: .semibold))
            }
            .buttonStyle(VellumPillButtonStyle(.primary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
    }
}

private struct TodayHeader: View {
    let model: TodayScreenModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.dateLine)
                .font(.vellumMono(11.5))
                .tracking(1.6)
                .foregroundStyle(VellumTheme.muted)

            Text(model.greeting)
                .font(.vellumSans(44, weight: .medium))
                .foregroundStyle(VellumTheme.ink)
                .padding(.top, 6)

            if let digestSubline = model.digestSubline {
                Text(digestSubline)
                    .font(.vellumCaveat(24))
                    .foregroundStyle(VellumTheme.mutedDark)
                    .padding(.top, 4)
            }
        }
    }
}

private struct TodayLeftColumn: View {
    @Bindable var model: VellumAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodaySectionHeader(title: "WHERE YOU LEFT OFF")
                .padding(.bottom, 10)

            VStack(spacing: 9) {
                ForEach(model.today.recentNotes) { note in
                    TodayRecentNoteCard(note: note) {
                        Task { await model.openNote(note.id) }
                    }
                }
            }

            TodaySectionHeader(title: "LOOSE THREADS")
                .padding(.top, 20)
                .padding(.bottom, 10)

            VellumFlowLayout(spacing: 9, lineSpacing: 9) {
                ForEach(model.today.looseThreads) { entity in
                    TodayEntityChip(entity: entity) {
                        model.graphScreen.selectEntity(named: entity.name)
                        Task { await model.navigate(to: .graph) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct TodayRightColumn: View {
    @Bindable var model: VellumAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodaySectionHeader(
                title: "OPEN TASKS",
                count: model.today.totalOpenTaskCount
            )
            .padding(.bottom, 10)

            TodayTasksPanel(model: model)

            if let excerpt = model.today.fromYourNotes {
                TodayFromNotesCard(excerpt: excerpt) {
                    Task { await model.openNote(excerpt.id) }
                }
                .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct TodaySectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            if let count {
                Text("\(count)")
                    .foregroundStyle(VellumTheme.mutedCount)
            }
        }
        .font(.vellumMono(11))
        .tracking(1.4)
        .foregroundStyle(VellumTheme.muted)
    }
}

private struct TodayRecentNoteCard: View {
    let note: TodayRecentNote
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 16) {
                VellumDotGrid(
                    spacing: 13,
                    dotColor: VellumTheme.ink(0.12),
                    background: VellumTheme.field
                )
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    Text(note.title)
                        .font(.vellumSans(20, weight: .semibold))
                        .foregroundStyle(VellumTheme.ink)
                        .lineLimit(1)

                    if !note.previewText.isEmpty {
                        Text(note.previewText)
                            .font(.vellumCaveat(19))
                            .foregroundStyle(VellumTheme.mutedDark)
                            .lineLimit(2)
                            .padding(.top, 3)
                    }

                    Text("\(noteTypeLabel) · \(note.relativeTime)")
                        .font(.vellumMono(11))
                        .foregroundStyle(VellumTheme.muted)
                        .lineLimit(1)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                VellumTheme.card,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(VellumTheme.ink(0.18), lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var noteTypeLabel: String {
        switch note.noteType {
        case .note: "NOTE"
        case .pdf: "PDF"
        case .deck: "DECK"
        case .image: "IMAGE"
        case .audio: "AUDIO"
        }
    }
}

private struct TodayEntityChip: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let entity: TodayLooseThread
    let select: () -> Void

    var body: some View {
        let shape = OrganicPillShape(variant: 0, isOrganic: vellumWobble)

        Button(action: select) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(entity.name)
                    .font(.vellumSans(16.5, weight: .medium))
                    .foregroundStyle(VellumTheme.bodyInk)
                    .lineLimit(1)

                Text("\(entity.sourceCount)")
                    .font(.vellumMono(11))
                    .foregroundStyle(VellumTheme.muted)
            }
            .padding(.horizontal, 17)
            .frame(minHeight: 46)
            .background {
                shape
                    .fill(VellumTheme.ink(0.09))
                    .offset(x: 2, y: 3)
                shape.fill(VellumTheme.field)
            }
            .overlay {
                shape.strokeBorder(VellumTheme.ink(0.3), lineWidth: 1.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        switch entity.kind {
        case .person: VellumTheme.accent
        case .topic: VellumTheme.spaceGreen
        case .document: VellumTheme.spaceBlue
        }
    }
}

private struct TodayTasksPanel: View {
    @Bindable var model: VellumAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.today.openTasks.isEmpty, model.today.hasLoadedTasks {
                Text("No open tasks.")
                    .font(.vellumCaveat(21))
                    .foregroundStyle(VellumTheme.mutedDark)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.today.openTasks) { task in
                    TodayTaskRow(task: task) {
                        Task {
                            await model.today.toggleTask(
                                id: task.id,
                                isDone: !task.isDone
                            )
                        }
                    }
                }
            }

            Button {
                Task { await model.navigate(to: .tasks) }
            } label: {
                Text("see all tasks →")
                    .font(.vellumSans(16.5, weight: .medium))
                    .foregroundStyle(VellumTheme.accentDark)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .vellumFloatingChrome(.panel)
    }
}

private struct TodayTaskRow: View {
    let task: TodayOpenTask
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Button(action: toggle) {
                TodayTaskCheckbox(isDone: task.isDone)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark task open" : "Complete task")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.text)
                    .font(.vellumSans(17))
                    .foregroundStyle(task.isDone ? VellumTheme.mutedDark : VellumTheme.bodyInk)
                    .strikethrough(task.isDone, color: VellumTheme.mutedDark)
                    .fixedSize(horizontal: false, vertical: true)

                Text(task.sourceNoteTitle)
                    .font(.vellumMono(11))
                    .foregroundStyle(VellumTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .stroke(
                    VellumTheme.ink(0.16),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
                .frame(height: 1)
        }
    }
}

private struct TodayTaskCheckbox: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let isDone: Bool

    var body: some View {
        let shape = VellumOrganicRectangle(
            topLeading: 9,
            bottomLeading: 4,
            bottomTrailing: 10,
            topTrailing: 5,
            straightRadius: 6,
            isOrganic: vellumWobble
        )

        ZStack {
            shape.fill(VellumTheme.card)
            shape.stroke(VellumTheme.ink, lineWidth: 2)

            if isDone {
                Text("✓")
                    .font(.vellumCaveat(24, weight: .semibold))
                    .foregroundStyle(VellumTheme.accent)
                    .offset(y: -1)
            }
        }
        .frame(width: 26, height: 26)
        .padding(.top, 2)
    }
}

private struct TodayFromNotesCard: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let excerpt: TodayNoteExcerpt
    let open: () -> Void

    var body: some View {
        let shape = VellumOrganicRectangle(
            topLeading: 10,
            bottomLeading: 28,
            bottomTrailing: 10,
            topTrailing: 26,
            straightRadius: 14,
            isOrganic: vellumWobble
        )

        VStack(alignment: .leading, spacing: 0) {
            Text("FROM YOUR NOTES")
                .font(.vellumMono(11))
                .tracking(1.4)
                .foregroundStyle(VellumTheme.muted)

            if !excerpt.previewText.isEmpty {
                Text(excerpt.previewText)
                    .font(.vellumCaveat(22))
                    .foregroundStyle(VellumTheme.bodyInk)
                    .lineLimit(3)
                    .padding(.top, 6)
            }

            Button(action: open) {
                Text("\(excerpt.title) →")
                    .font(.vellumSans(15.5, weight: .medium))
                    .foregroundStyle(VellumTheme.accentDark)
                    .lineLimit(1)
                    .padding(.top, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VellumTheme.sidebar, in: shape)
        .overlay {
            shape.stroke(VellumTheme.ink(0.24), lineWidth: 1.5)
        }
    }
}

private struct TodayTwoColumnLayout: Layout {
    let ratio: CGFloat
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let totalWidth = proposal.width ?? 0
        let contentWidth = max(0, totalWidth - spacing)
        let leftWidth = contentWidth * ratio / (ratio + 1)
        let rightWidth = contentWidth - leftWidth
        let leftSize = subviews[0].sizeThatFits(
            ProposedViewSize(width: leftWidth, height: proposal.height)
        )
        let rightSize = subviews[1].sizeThatFits(
            ProposedViewSize(width: rightWidth, height: proposal.height)
        )
        return CGSize(width: totalWidth, height: max(leftSize.height, rightSize.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else { return }
        let contentWidth = max(0, bounds.width - spacing)
        let leftWidth = contentWidth * ratio / (ratio + 1)
        let rightWidth = contentWidth - leftWidth

        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: leftWidth, height: bounds.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + leftWidth + spacing, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: rightWidth, height: bounds.height)
        )
    }
}
