import SwiftUI
import VellumCore

/// The horizontally scrolling row of entity chips under the note header.
struct NoteEntityChipsRow: View {
    let entities: [Entity]
    let onSelect: (Entity) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(entities) { entity in
                    Button {
                        onSelect(entity)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(color(for: entity.kind))
                                .frame(width: 6, height: 6)
                            Text(entity.name)
                                .lineLimit(1)
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(VellumTheme.bodyMuted)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(VellumTheme.popover, in: Capsule())
                        .overlay {
                            Capsule().stroke(VellumTheme.ink(0.13), lineWidth: 1)
                        }
                        .shadow(color: VellumTheme.ink(0.14), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 9)
        }
        .scrollIndicators(.hidden)
    }

    private func color(for kind: EntityKind) -> Color {
        switch kind {
        case .person: VellumTheme.accent
        case .topic: VellumTheme.spaceGreen
        case .document: VellumTheme.spaceBlue
        }
    }
}
