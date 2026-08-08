import SwiftUI
import VellumCore

/// The one-line prompt over the canvas that opens the suggestions panel.
struct NoteAgentLine: View {
    let model: NoteScreenModel

    var body: some View {
        Button {
            model.isShowingSuggestions = true
        } label: {
            HStack(spacing: 3) {
                Text("\(model.pendingProposals.count) suggestions —")
                Text("review")
                    .foregroundStyle(VellumTheme.accentDark)
                    .overlay(alignment: .bottom) {
                        VellumDottedLine(color: VellumTheme.accent)
                            .frame(height: 1)
                            .offset(y: 1)
                    }
            }
            .font(.vellumSans(13.5, italic: true))
            .foregroundStyle(VellumTheme.muted)
        }
        .buttonStyle(.plain)
    }
}

/// The agent's pending-proposal review panel, over a tap-to-dismiss scrim.
struct NoteSuggestionsOverlay: View {
    let model: NoteScreenModel

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.isShowingSuggestions = false
                }

            panel
                .frame(width: 370)
                .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggestions")
                        .font(.vellumSans(22, weight: .semibold))
                    Text("\(model.pendingProposals.count) ready to review")
                        .font(.vellumMono(10.5))
                        .foregroundStyle(VellumTheme.mutedCount)
                }
                Spacer()
                Button("×") {
                    model.isShowingSuggestions = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 18))
                .foregroundStyle(VellumTheme.mutedCount)
                .accessibilityLabel("Close suggestions")
            }

            if let tags = model.note?.tags, !tags.isEmpty {
                NoteTagsRow(tags: tags)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.pendingProposals) { proposal in
                        card(proposal)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(VellumTheme.ink(0.14), lineWidth: 1)
        }
        .shadow(color: VellumTheme.ink(0.18), radius: 18, x: -4, y: 12)
    }

    private func card(_ proposal: AgentProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.title)
                    .font(.vellumSans(16, weight: .semibold))
                    .foregroundStyle(VellumTheme.ink)
                Spacer()
                Text("\(Int((proposal.confidence * 100).rounded()))%")
                    .font(.vellumMono(10.5, weight: .medium))
                    .foregroundStyle(VellumTheme.accentDark)
            }

            Text(operationDescription(proposal.operation))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(VellumTheme.bodyMuted)

            Text(proposal.explanation)
                .font(.system(size: 12.5))
                .foregroundStyle(VellumTheme.mutedDark)
                .lineSpacing(4)

            HStack(spacing: 10) {
                Button("Accept") {
                    Task { await model.accept(proposal) }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(VellumTheme.paper)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(VellumTheme.ink, in: Capsule())

                Button("Reject") {
                    Task { await model.reject(proposal) }
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(VellumTheme.mutedDark)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VellumTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(VellumTheme.ink(0.1), lineWidth: 1)
        }
    }

    private func operationDescription(_ operation: AgentOperation) -> String {
        switch operation {
        case .addTag(let tag):
            "Add tag “\(tag)”"
        case .suggestTitle(let title):
            "Rename note to “\(title)”"
        case .createSummary(let summary):
            "Create summary: \(summary)"
        case .fileToSpace(let spaceName, let color):
            "File in \(spaceName) · \(color.rawValue)"
        case .linkNotes(let targetNoteID, let kind):
            "Link to \(model.noteTitles[targetNoteID] ?? targetNoteID.uuidString) · \(kind.rawValue)"
        case .extractTask(let text, _):
            "Extract task: \(text)"
        case .extractEntity(let name, let kind, _, _):
            "Extract \(kind.rawValue): \(name)"
        }
    }
}

private struct NoteTagsRow: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 8) {
            Text("TAGS")
                .font(.vellumMono(10.5))
                .foregroundStyle(VellumTheme.mutedCount)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                        Text(tag)
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
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
    }
}
