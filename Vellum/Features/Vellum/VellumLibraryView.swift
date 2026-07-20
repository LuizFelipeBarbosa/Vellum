import Observation
import SwiftUI
import VellumCore

struct VellumLibraryView: View {
    @Bindable var model: VellumAppModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        @Bindable var library = model.library

        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Library")
                        .font(.vellumNewsreader(34, weight: .medium))
                    Spacer()
                    HStack(spacing: 6) {
                        selectionChip
                        filterChip("All", type: nil)
                        ForEach(NoteType.allCases, id: \.rawValue) { type in
                            filterChip(type.libraryFilterLabel, type: type)
                        }
                    }
                }
                .padding(.bottom, 6)

                Text(library.countLine)
                    .font(.system(size: 13))
                    .foregroundStyle(VellumTheme.muted)
                    .padding(.bottom, 16)

                ScrollView {
                    if library.cards.isEmpty && !library.isLoading {
                        VStack(spacing: 14) {
                            Text("Nothing here yet")
                                .font(.vellumNewsreader(24, italic: true))
                                .foregroundStyle(VellumTheme.bodyMuted)
                            Button("New note", action: createNote)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(VellumTheme.paper)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(VellumTheme.ink, in: Capsule())
                                .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(library.cards) { card in
                                libraryCard(
                                    card,
                                    isSelecting: library.isSelecting,
                                    isSelected: library.selectedIDs.contains(card.id)
                                )
                            }
                        }
                        .padding(.bottom, 80)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)

            if !library.isSelecting {
                Button(action: createNote) {
                    VellumPencilGlyph(size: 24)
                        .frame(width: 58, height: 58)
                        .background(VellumTheme.ink, in: Circle())
                        .shadow(color: VellumTheme.ink(0.3), radius: 12, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 30)
                .padding(.bottom, 26)
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

    private var selectionChip: some View {
        let selected = model.library.isSelecting
        return Button(selected ? "Done" : "Select") {
            if selected {
                model.library.endSelecting()
            } else {
                model.library.beginSelecting()
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(selected ? VellumTheme.paper : VellumTheme.bodyMuted)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(selected ? VellumTheme.ink : .clear, in: Capsule())
        .overlay(Capsule().stroke(selected ? VellumTheme.ink : VellumTheme.ink(0.16), lineWidth: 1))
        .buttonStyle(.plain)
    }

    private var selectionBar: some View {
        HStack(spacing: 20) {
            Text("\(model.library.selectedIDs.count) selected")
                .font(.system(size: 13))
                .foregroundStyle(VellumTheme.muted)

            Spacer()

            Menu("Move to Space…") {
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
            }
            .disabled(model.library.selectedIDs.isEmpty)

            Button("Move to Trash", role: .destructive) {
                model.library.isConfirmingBulkDelete = true
            }
            .disabled(model.library.selectedIDs.isEmpty)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .background(VellumTheme.card)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(VellumTheme.ink(0.08))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func libraryCard(
        _ card: LibraryCardData,
        isSelecting: Bool,
        isSelected: Bool
    ) -> some View {
        let cardView = VellumLibraryCardView(
            card: card,
            isSelecting: isSelecting,
            isSelected: isSelected
        ) {
            if isSelecting {
                model.library.toggleSelection(card.id)
            } else {
                Task { await model.navigate(to: .note(card.id)) }
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
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(selected ? VellumTheme.paper : VellumTheme.bodyMuted)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(selected ? VellumTheme.ink : .clear, in: Capsule())
        .overlay(Capsule().stroke(selected ? VellumTheme.ink : VellumTheme.ink(0.16), lineWidth: 1))
        .buttonStyle(.plain)
    }

    private func createNote() {
        Task {
            guard let noteID = await model.library.createNote() else { return }
            await model.refreshStats()
            await model.navigate(to: .note(noteID))
        }
    }
}

private struct VellumLibraryCardView: View {
    let card: LibraryCardData
    let isSelecting: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    preview

                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? VellumTheme.accent : VellumTheme.mutedControl)
                            .padding(8)
                    }
                }
                    .frame(height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(card.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(VellumTheme.ink)
                    .lineLimit(1)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                HStack(spacing: 6) {
                    Circle().fill(card.dotColor).frame(width: 6, height: 6)
                    Text(card.metaLine)
                        .font(.system(size: 12))
                        .foregroundStyle(VellumTheme.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(VellumTheme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(VellumTheme.ink(0.09), lineWidth: 1)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(VellumTheme.accent, lineWidth: 2)
                    }
                }
            }
            .shadow(color: VellumTheme.ink(0.05), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        switch card.treatment {
        case .handwritten:
            ZStack(alignment: .topLeading) {
                VellumDotGrid(spacing: 18, dotColor: VellumTheme.ink(0.13), background: VellumTheme.libraryBody)
                Text(card.previewText)
                    .font(.vellumCaveat(21))
                    .foregroundStyle(VellumTheme.bodyInk)
                    .lineSpacing(5.25)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        case .stripe(let label):
            ZStack {
                VellumDiagonalStripes(background: VellumTheme.stripeCard, stripe: VellumTheme.ink(0.05), spacing: 16)
                Text(label)
                    .font(.vellumMono(11))
                    .foregroundStyle(VellumTheme.mutedControl)
            }
        case .audio:
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array([14.0, 26.0, 18.0, 32.0, 12.0, 22.0, 16.0].enumerated()), id: \.offset) { index, height in
                        Capsule()
                            .fill(index == 2 ? VellumTheme.accent : VellumTheme.waveform)
                            .frame(width: 3, height: height)
                    }
                }
                Text(card.previewText)
                    .font(.vellumMono(11))
                    .foregroundStyle(VellumTheme.mutedControl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VellumTheme.stripeCard)
        }
    }
}
