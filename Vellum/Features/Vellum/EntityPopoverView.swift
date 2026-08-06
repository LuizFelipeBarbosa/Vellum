import SwiftUI
import VellumCore

struct EntityPopoverView: View {
    let entity: Entity
    @Bindable var model: NoteScreenModel
    @Bindable var app: VellumAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(entity.name)
                    .font(.vellumSans(17, weight: .semibold))
                Spacer()
                Button("×") {
                    model.selectedEntity = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(VellumTheme.mutedCount)
                .padding(.horizontal, 2)
                .accessibilityLabel("Close entity details")
            }

            Text("\(entity.kind.rawValue) · \(sourceCountLabel)")
                .font(.system(size: 12))
                .foregroundStyle(VellumTheme.muted)
                .padding(.top, 2)

            if let excerpt = latestExcerpt {
                Text(excerpt)
                    .font(.system(size: 12.5))
                    .foregroundStyle(VellumTheme.bodyMuted)
                    .lineSpacing(6.25)
                    .padding(.top, 9)
            }

            HStack(spacing: 14) {
                Button("View in graph →") {
                    model.selectedEntity = nil
                    app.graphScreen.selectEntity(named: entity.name)
                    Task { await app.navigate(to: .graph) }
                }
                Button("Ask →") {
                    model.selectedEntity = nil
                    app.askAbout("Tell me about \(entity.name)")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(VellumTheme.accentDark)
            .padding(.top, 11)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.18), radius: 18, y: 12)
    }

    private var sourceCountLabel: String {
        "\(entity.sources.count) \(entity.sources.count == 1 ? "source" : "sources")"
    }

    private var latestExcerpt: String? {
        entity.sources.reversed().compactMap(\.excerpt).first
    }
}
