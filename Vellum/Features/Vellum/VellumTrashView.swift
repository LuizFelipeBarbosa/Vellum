import SwiftUI

struct VellumTrashView: View {
    @Bindable var model: VellumAppModel

    var body: some View {
        @Bindable var trash = model.trashScreen

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trash")
                    .font(.vellumNewsreader(34, weight: .medium))
                Spacer()
                Button("Empty Trash") {
                    trash.isConfirmingEmptyTrash = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VellumTheme.spaceRed)
                .buttonStyle(.plain)
                .disabled(trash.rows.isEmpty)
            }
            .padding(.bottom, 16)

            ScrollView {
                if trash.rows.isEmpty {
                    Text("Trash is empty")
                        .font(.vellumNewsreader(24, italic: true))
                        .foregroundStyle(VellumTheme.bodyMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(trash.rows) { row in
                            trashRow(row, trash: trash)
                        }
                    }
                    .padding(.bottom, 26)
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .background(VellumTheme.paper)
        .confirmationDialog(
            "Empty Trash?",
            isPresented: $trash.isConfirmingEmptyTrash,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) {
                Task {
                    await trash.emptyTrash()
                    await model.refreshStats()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(trash.rows.count) notes. This can't be undone.")
        }
        .confirmationDialog(
            "Delete permanently?",
            isPresented: Binding(
                get: { trash.pendingPurgeID != nil },
                set: { isPresented in
                    if !isPresented { trash.cancelPurge() }
                }
            ),
            titleVisibility: .visible,
            presenting: trash.pendingPurgeID
        ) { noteID in
            Button("Delete Forever", role: .destructive) {
                Task {
                    await trash.confirmPurge(noteID)
                    await model.refreshStats()
                    await model.library.refresh()
                }
            }
            Button("Cancel", role: .cancel) {
                trash.cancelPurge()
            }
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert(
            "Vellum",
            isPresented: Binding(
                get: { trash.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { trash.errorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                trash.errorMessage = nil
            }
        } message: {
            Text(trash.errorMessage ?? "An unknown error occurred.")
        }
        .task { await trash.refresh() }
    }

    private func trashRow(_ row: TrashRow, trash: TrashScreenModel) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(VellumTheme.ink)
                    .lineLimit(1)
                Text(subtitle(for: row))
                    .font(.system(size: 12))
                    .foregroundStyle(VellumTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button("Restore") {
                Task {
                    await trash.restore(row.id)
                    await model.refreshStats()
                    await model.library.refresh()
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(VellumTheme.accentDark)
            .buttonStyle(.plain)

            Button("Delete Forever") {
                trash.requestPurge(row.id)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(VellumTheme.spaceRed)
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(VellumTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VellumTheme.ink(0.09), lineWidth: 1))
        .shadow(color: VellumTheme.ink(0.05), radius: 1, y: 1)
    }

    private func subtitle(for row: TrashRow) -> String {
        var subtitle = "Deleted \(relativeTime(for: row.deletedAt))"
        if let spaceName = row.spaceName {
            subtitle += " · \(spaceName)"
        }
        return subtitle
    }

    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
