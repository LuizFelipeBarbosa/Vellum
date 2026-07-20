import SwiftUI
import VellumCore

struct SpaceEditorContext: Identifiable {
    let id = UUID()
    let parent: Space?
}

struct SpaceEditorView: View {
    let model: VellumAppModel
    let context: SpaceEditorContext

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: SpaceColor = .blue

    private var title: String {
        if let parent = context.parent {
            "New Subspace of \(parent.name)"
        } else {
            "New Space"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.vellumNewsreader(24, weight: .semibold))
                    .foregroundStyle(VellumTheme.ink)

                TextField("Name", text: $name)
                    .font(.system(size: 16))
                    .foregroundStyle(VellumTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        VellumTheme.ink(0.05),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                HStack(spacing: 18) {
                    ForEach(SpaceColor.allCases, id: \.rawValue) { colorCase in
                        Button {
                            color = colorCase
                        } label: {
                            Circle()
                                .fill(VellumTheme.color(for: colorCase))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            color == colorCase ? VellumTheme.accent : .clear,
                                            lineWidth: 2
                                        )
                                        .padding(-4)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(colorCase.rawValue.capitalized)
                    }
                }

                Spacer()

                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VellumTheme.mutedControl)

                    Spacer()

                    Button("Create") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            await model.createSpace(
                                name: trimmedName,
                                color: color,
                                parentID: context.parent?.id
                            )
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VellumTheme.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(28)
            .background(VellumTheme.paper)
        }
        .presentationDetents([.height(320)])
    }
}
