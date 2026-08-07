import SwiftUI
import VellumCore

struct VellumLibraryView: View {
    @Bindable var model: VellumAppModel
    @State private var isImportingPDF = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        @Bindable var library = model.library

        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 18)

                filterRow
                    .padding(.bottom, 16)

                if library.unsupportedNoteCount > 0 {
                    unsupportedNotesBanner(count: library.unsupportedNoteCount)
                        .padding(.bottom, 16)
                }

                libraryContent
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)

            if !library.isSelecting {
                floatingNewNoteMenu
            }
        }
        .background(VellumTheme.paper)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if library.isSelecting {
                selectionBar
            }
        }
        .alert(
            "Rename Note",
            isPresented: Binding(
                get: { library.renamingNoteID != nil },
                set: { isPresented in
                    if !isPresented { library.cancelRename() }
                }
            ),
            presenting: library.renamingNoteID
        ) { noteID in
            TextField("Title", text: $library.renameDraft)
            Button("Cancel", role: .cancel) {
                library.cancelRename()
            }
            Button("Rename") {
                Task { await library.commitRename(noteID: noteID) }
            }
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: Binding(
                get: { library.notePendingDeletionID != nil },
                set: { isPresented in
                    if !isPresented { library.cancelDelete() }
                }
            ),
            titleVisibility: .visible,
            presenting: library.notePendingDeletionID
        ) { noteID in
            Button("Move to Trash", role: .destructive) {
                Task {
                    let id = await library.confirmDelete(noteID)
                    await model.refreshStats()
                    if let id {
                        model.notifyTrashed([id])
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                library.cancelDelete()
            }
        } message: { _ in
            Text("The note moves to the Trash. You can restore it there later.")
        }
        .confirmationDialog(
            "Move \(library.selectedIDs.count) notes to Trash?",
            isPresented: $library.isConfirmingBulkDelete,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task {
                    let ids = await library.deleteSelected()
                    await model.refreshStats()
                    model.notifyTrashed(ids)
                }
            }
            Button("Cancel", role: .cancel) {
                library.isConfirmingBulkDelete = false
            }
        } message: {
            Text("The notes move to the Trash. You can restore them there later.")
        }
        .pdfImporter(isPresented: $isImportingPDF, model: model)
        .alert(
            "Vellum",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { library.errorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                library.errorMessage = nil
            }
        } message: {
            Text(library.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.library.libraryTitle)
                    .font(.vellumSans(42, weight: .medium))
                    .foregroundStyle(VellumTheme.ink)
                    .lineLimit(1)

                Text(model.library.countLine)
                    .font(.vellumCaveat(21))
                    .foregroundStyle(VellumTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)
            displayModeToggle
        }
    }

    private var displayModeToggle: some View {
        HStack(spacing: 4) {
            displayModeButton("pinboard", mode: .pinboard)
            displayModeButton("field guide", mode: .fieldGuide)
        }
        .padding(4)
        .background(VellumTheme.sidebar, in: Capsule())
    }

    private func displayModeButton(
        _ label: String,
        mode: LibraryDisplayMode
    ) -> some View {
        let isActive = model.library.displayMode == mode
        return Button(label) {
            model.library.displayMode = mode
        }
        .font(.vellumSans(16, weight: isActive ? .semibold : .medium))
        .foregroundStyle(isActive ? VellumTheme.ink : VellumTheme.bodyMuted)
        .frame(minWidth: 104, minHeight: 40)
        .padding(.horizontal, 5)
        .background(isActive ? VellumTheme.card : .clear, in: Capsule())
        .overlay {
            if isActive {
                Capsule()
                    .stroke(VellumTheme.ink(0.2), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var filterRow: some View {
        VellumFlowLayout(spacing: 8, lineSpacing: 8) {
            selectionChip
            filterChip("All", type: nil)
            ForEach(NoteType.allCases, id: \.rawValue) { type in
                filterChip(type.libraryFilterLabel, type: type)
            }
        }
    }

    private var libraryContent: some View {
        ScrollView {
            if model.library.cards.isEmpty && !model.library.isLoading {
                emptyState
            } else {
                switch model.library.displayMode {
                case .pinboard:
                    pinboard
                case .fieldGuide:
                    fieldGuide
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var pinboard: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(model.library.cards) { card in
                libraryCard(
                    card,
                    layout: .pinboard,
                    isSelecting: model.library.isSelecting,
                    isSelected: model.library.selectedIDs.contains(card.id)
                )
            }
        }
        .padding(.bottom, 90)
    }

    private var fieldGuide: some View {
        LazyVStack(alignment: .leading, spacing: 30) {
            ForEach(model.library.cardGroups) { group in
                fieldGuideSection(group)
            }
        }
        .padding(.bottom, 90)
    }

    private func fieldGuideSection(_ group: LibraryCardGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldGuideHeader(group)

            ForEach(group.cards) { card in
                libraryCard(
                    card,
                    layout: .fieldGuide,
                    isSelecting: model.library.isSelecting,
                    isSelected: model.library.selectedIDs.contains(card.id)
                )
            }
        }
    }

    private func fieldGuideHeader(_ group: LibraryCardGroup) -> some View {
        HStack(spacing: 9) {
            VellumBlobDot(color: group.color, size: 11)

            Text(group.name)
                .font(.vellumCaveat(27))
                .foregroundStyle(VellumTheme.ink)
                .lineLimit(1)

            Rectangle()
                .stroke(
                    VellumTheme.ink(0.24),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
                .frame(maxWidth: .infinity)
                .frame(height: 1)

            Text("\(group.cardCount) \(group.cardCount == 1 ? "note" : "notes")")
                .font(.vellumMono(11))
                .foregroundStyle(VellumTheme.muted)
                .lineLimit(1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            VellumDotGrid(
                spacing: 15,
                dotColor: VellumTheme.ink(0.12),
                background: VellumTheme.card
            )
            .frame(width: 118, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        VellumTheme.ink(0.28),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                    )
            }
            .rotationEffect(.degrees(-2.5))

            Text("Nothing here yet")
                .font(.vellumSans(30, italic: true))
                .foregroundStyle(VellumTheme.bodyInk)

            Text("A blank page is an invitation.")
                .font(.vellumCaveat(22))
                .foregroundStyle(VellumTheme.muted)

            HStack(spacing: 14) {
                Menu {
                    Button("New Note", action: createNote)
                    Button("New from PDF") {
                        isImportingPDF = true
                    }
                } label: {
                    Text("+ new note")
                        .font(.vellumSans(17, weight: .semibold))
                }
                .buttonStyle(VellumPillButtonStyle(.primary))

                Button("show everything") {
                    model.library.filter = nil
                    model.library.selectedSpaceID = nil
                }
                .font(.vellumSans(17, weight: .medium))
                .buttonStyle(VellumPillButtonStyle(.outline))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.bottom, 90)
    }

    private var floatingNewNoteMenu: some View {
        Menu {
            Button("New Note", action: createNote)
            Button("New from PDF") {
                isImportingPDF = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(VellumTheme.ink(0.24))
                    .frame(width: 58, height: 58)
                    .offset(x: 4, y: 5)

                VellumPencilGlyph(size: 24)
                    .frame(width: 58, height: 58)
                    .background(VellumTheme.accent, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(VellumTheme.ink, lineWidth: 1.5)
                    }
            }
            .frame(width: 64, height: 66)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 30)
        .padding(.bottom, 26)
    }

    private func unsupportedNotesBanner(count: Int) -> some View {
        let message = count == 1
            ? "1 note needs a newer version of Vellum"
            : "\(count) notes need a newer version of Vellum"

        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(VellumTheme.accentDark)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VellumTheme.bodyMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(VellumTheme.ink(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }

    private var selectionChip: some View {
        let selected = model.library.isSelecting
        return Button(selected ? "Done" : "Select") {
            if selected {
                model.library.endSelecting()
            } else {
                model.library.beginSelecting()
            }
        }
        .font(.vellumSans(17, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? VellumTheme.paper : VellumTheme.bodyMuted)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .background(selected ? VellumTheme.ink : .clear, in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    selected ? VellumTheme.ink : VellumTheme.ink(0.2),
                    lineWidth: 1.5
                )
        }
        .buttonStyle(.plain)
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Text("\(model.library.selectedIDs.count) selected")
                .font(.vellumMono(11))
                .foregroundStyle(VellumTheme.muted)

            Spacer()

            moveToSpaceMenu

            Button("Move to Trash", role: .destructive) {
                model.library.isConfirmingBulkDelete = true
            }
            .font(.vellumSans(16, weight: .semibold))
            .buttonStyle(VellumPillButtonStyle(.primary))
            .disabled(model.library.selectedIDs.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .vellumFloatingChrome(.panel)
        .padding(.horizontal, 30)
        .padding(.bottom, 14)
    }

    private var moveToSpaceMenu: some View {
        Menu {
            Button("Unfiled") {
                Task { await model.library.moveSelected(toSpaceID: nil) }
            }

            ForEach(
                model.library.spaces.filter { $0.space.parentID == nil },
                id: \.space.id
            ) { root in
                Button(root.space.name) {
                    Task { await model.library.moveSelected(toSpaceID: root.space.id) }
                }

                ForEach(
                    model.library.spaces.filter { $0.space.parentID == root.space.id },
                    id: \.space.id
                ) { child in
                    Button("— \(child.space.name)") {
                        Task { await model.library.moveSelected(toSpaceID: child.space.id) }
                    }
                }
            }
        } label: {
            Text("Move to Space…")
                .font(.vellumSans(16, weight: .medium))
        }
        .buttonStyle(VellumPillButtonStyle(.outline))
        .disabled(model.library.selectedIDs.isEmpty)
    }

    @ViewBuilder
    private func libraryCard(
        _ card: LibraryCardData,
        layout: LibraryCardLayout,
        isSelecting: Bool,
        isSelected: Bool
    ) -> some View {
        let tags = model.library.summaries.first { $0.id == card.id }?.tags ?? []
        let action: () -> Void = {
            if isSelecting {
                model.library.toggleSelection(card.id)
            } else {
                Task { await model.openNote(card.id) }
            }
        }
        let cardView = Group {
            switch layout {
            case .pinboard:
                VellumLibraryCardView(
                    card: card,
                    tags: tags,
                    isSelecting: isSelecting,
                    isSelected: isSelected,
                    action: action
                )
            case .fieldGuide:
                VellumLibraryRowView(
                    card: card,
                    tags: tags,
                    isSelecting: isSelecting,
                    isSelected: isSelected,
                    action: action
                )
            }
        }

        if isSelecting {
            cardView
        } else {
            cardView.contextMenu {
                Button {
                    model.library.beginRename(card)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    model.library.requestDelete(card.id)
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
        }
    }

    private func filterChip(_ label: String, type: NoteType?) -> some View {
        let selected = model.library.filter == type
        return Button(label) {
            model.library.filter = type
        }
        .font(.vellumSans(17, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? VellumTheme.paper : VellumTheme.bodyMuted)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .background(selected ? VellumTheme.ink : .clear, in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    selected ? VellumTheme.ink : VellumTheme.ink(0.2),
                    lineWidth: 1.5
                )
        }
        .buttonStyle(.plain)
    }

    private func createNote() {
        Task {
            guard let noteID = await model.library.createNote() else { return }
            await model.refreshStats()
            await model.openNote(noteID, isNewlyCreated: true)
        }
    }
}

private enum LibraryCardLayout {
    case pinboard
    case fieldGuide
}

private struct VellumLibraryCardView: View {
    let card: LibraryCardData
    let tags: [String]
    let isSelecting: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VellumLibraryPreview(card: card)

                    if isSelecting {
                        selectionBadge
                            .padding(8)
                    }
                }
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(card.title)
                    .font(.vellumSans(19, weight: .semibold))
                    .foregroundStyle(VellumTheme.ink)
                    .lineLimit(1)
                    .padding(.top, 13)
                    .padding(.bottom, 6)

                if !tags.isEmpty {
                    VellumTagChipsRow(tags: tags)
                        .padding(.bottom, 8)
                }

                HStack(spacing: 7) {
                    Circle()
                        .fill(card.dotColor)
                        .frame(width: 8, height: 8)
                    Text(card.metaLine)
                        .font(.vellumMono(11))
                        .foregroundStyle(VellumTheme.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(VellumTheme.card, in: cardShape)
            .overlay { cardBorder }
        }
        .buttonStyle(.plain)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var cardBorder: some View {
        ZStack {
            cardShape
                .stroke(VellumTheme.ink(0.18), lineWidth: 1.5)
            if isSelected {
                cardShape
                    .stroke(VellumTheme.accent, lineWidth: 2)
            }
        }
    }

    private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isSelected ? VellumTheme.accent : VellumTheme.mutedControl)
            .background(VellumTheme.card, in: Circle())
    }
}

private struct VellumLibraryRowView: View {
    let card: LibraryCardData
    let tags: [String]
    let isSelecting: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 18) {
                ZStack(alignment: .topTrailing) {
                    VellumLibraryPreview(card: card, handwrittenLineLimit: 4)

                    if isSelecting {
                        selectionBadge
                            .padding(7)
                    }
                }
                .frame(width: 132, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text(card.title)
                        .font(.vellumSans(20, weight: .semibold))
                        .foregroundStyle(VellumTheme.ink)
                        .lineLimit(1)

                    Text(card.previewText)
                        .font(.vellumSans(16))
                        .foregroundStyle(VellumTheme.mutedDark)
                        .lineLimit(1)

                    if !tags.isEmpty {
                        VellumTagChipsRow(tags: tags)
                    }

                    Spacer(minLength: 4)

                    Text(card.metaLine)
                        .font(.vellumMono(11))
                        .foregroundStyle(VellumTheme.muted)
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VellumTheme.card, in: cardShape)
            .overlay { cardBorder }
        }
        .buttonStyle(.plain)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var cardBorder: some View {
        ZStack {
            cardShape
                .stroke(VellumTheme.ink(0.18), lineWidth: 1.5)
            if isSelected {
                cardShape
                    .stroke(VellumTheme.accent, lineWidth: 2)
            }
        }
    }

    private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(isSelected ? VellumTheme.accent : VellumTheme.mutedControl)
            .background(VellumTheme.card, in: Circle())
    }
}

private struct VellumTagChipsRow: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tags.prefix(2).enumerated()), id: \.offset) { index, tag in
                Text(displayText(for: tag))
                    .font(.vellumMono(10.5))
                    .foregroundStyle(VellumTheme.bodyMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        VellumPillChrome(
                            fill: VellumTheme.ink(0.05),
                            border: VellumTheme.ink(0.14),
                            variant: index
                        )
                    }
                    .accessibilityLabel(tag)
            }
        }
    }

    private func displayText(for tag: String) -> String {
        tag.count > 12 ? String(tag.prefix(12)) + "…" : tag
    }
}

private struct VellumLibraryPreview: View {
    @Environment(\.vellumHandwritingPreviews) private var handwritingPreviews

    let card: LibraryCardData
    var handwrittenLineLimit: Int?

    init(card: LibraryCardData, handwrittenLineLimit: Int? = nil) {
        self.card = card
        self.handwrittenLineLimit = handwrittenLineLimit
    }

    @ViewBuilder
    var body: some View {
        switch card.treatment {
        case .handwritten:
            handwrittenPreview
        case .stripe(let label):
            stripePreview(label: label)
        case .audio:
            audioPreview
        }
    }

    private var handwrittenPreview: some View {
        ZStack(alignment: .topLeading) {
            VellumDotGrid(
                spacing: 18,
                dotColor: VellumTheme.ink(0.13),
                background: VellumTheme.libraryBody
            )
            Text(card.previewText)
                .font(handwritingPreviews ? .vellumCaveat(21) : .vellumSans(15))
                .foregroundStyle(VellumTheme.bodyInk)
                .lineSpacing(handwritingPreviews ? 5.25 : 3)
                .lineLimit(handwrittenLineLimit)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
    }

    private func stripePreview(label: String) -> some View {
        ZStack {
            VellumDiagonalStripes(
                background: VellumTheme.stripeCard,
                stripe: VellumTheme.ink(0.05),
                spacing: 16
            )
            Text(label)
                .font(.vellumMono(11))
                .foregroundStyle(VellumTheme.mutedControl)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
    }

    private var audioPreview: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 3) {
                ForEach(
                    Array([14.0, 26.0, 18.0, 32.0, 12.0, 22.0, 16.0].enumerated()),
                    id: \.offset
                ) { index, height in
                    Capsule()
                        .fill(index == 2 ? VellumTheme.accent : VellumTheme.waveform)
                        .frame(width: 3, height: height)
                }
            }
            Text(card.previewText)
                .font(.vellumMono(11))
                .foregroundStyle(VellumTheme.mutedControl)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VellumTheme.stripeCard)
    }
}
