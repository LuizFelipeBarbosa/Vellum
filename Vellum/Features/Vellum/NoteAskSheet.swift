import Foundation
import SwiftUI
import VellumCore

struct NoteAskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: NoteAskScreenModel
    let note: Note
    let onScrollToPage: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            NoteAskSheetHeader(noteTitle: note.title)

            if case .fallback(let reason) = model.availability {
                NoteAskFallbackBanner(reason: reason)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            NoteAskConversation(
                turns: model.turns,
                summary: model.summary,
                phase: model.phase,
                onSummarize: model.summarize,
                onCitation: openCitation
            )

            NoteAskInputBar(
                text: $model.inputText,
                isStreaming: model.phase == .streaming,
                onSubmit: model.ask
            )
        }
        .background(VellumTheme.paper)
        .presentationDetents([.medium, .large])
        .task { await model.start() }
        .onDisappear { model.cancel() }
    }

    private func openCitation(_ citation: Citation) {
        guard let pageID = citation.pageID,
              let index = note.pages.firstIndex(where: { $0.id == pageID }) else {
            return
        }
        onScrollToPage(index)
        dismiss()
    }
}

private struct NoteAskSheetHeader: View {
    let noteTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ASK THIS NOTE")
                .font(.vellumMono(11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(VellumTheme.accentDark)
            Text(noteTitle)
                .font(.vellumSans(24, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            VellumDashedRule()
                .stroke(
                    VellumTheme.ink(0.18),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
                )
                .frame(height: 1.5)
        }
    }
}

private struct NoteAskConversation: View {
    let turns: [NoteAskTurn]
    let summary: String?
    let phase: NoteAskScreenModel.Phase
    let onSummarize: () -> Void
    let onCitation: (Citation) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let summary {
                    NoteAskSummaryCard(summary: summary)
                }

                if turns.isEmpty, summary == nil {
                    NoteAskEmptyStateRow(
                        isStreaming: phase == .streaming,
                        action: onSummarize
                    )
                }

                ForEach(turns) { turn in
                    NoteAskTurnRow(turn: turn, onCitation: onCitation)
                }

                if case .error(let message) = phase {
                    NoteAskErrorBanner(message: message)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoteAskTurnRow: View {
    let turn: NoteAskTurn
    let onCitation: (Citation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoteAskQuestionChip(question: turn.question)

            if turn.answerText.isEmpty, !turn.isComplete {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("reading this note…")
                        .font(.vellumSans(17, italic: true))
                }
                .foregroundStyle(VellumTheme.muted)
            } else if !turn.answerText.isEmpty {
                Text(turn.answerText)
                    .font(.vellumSans(18.5))
                    .foregroundStyle(VellumTheme.bodyInk)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !turn.citations.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(turn.citations) { citation in
                            Button {
                                onCitation(citation)
                            } label: {
                                NoteAskCitationChip(citation: citation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct NoteAskQuestionChip: View {
    @Environment(\.vellumWobble) private var vellumWobble
    let question: String

    var body: some View {
        let shape = OrganicPillShape(variant: 2, isOrganic: vellumWobble)

        HStack {
            Spacer(minLength: 48)
            Text(question)
                .font(.vellumSans(17.5, weight: .medium))
                .foregroundStyle(VellumTheme.ink)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(VellumTheme.highlight.opacity(0.22), in: shape)
                .background {
                    shape
                        .fill(VellumTheme.ink(0.1))
                        .offset(x: 3, y: 3)
                }
                .overlay {
                    shape.strokeBorder(VellumTheme.ink(0.26), lineWidth: 1.25)
                }
        }
    }
}

private struct NoteAskCitationChip: View {
    @Environment(\.vellumWobble) private var vellumWobble
    let citation: Citation

    var body: some View {
        let shape = VellumOrganicRectangle(
            topLeading: 18,
            bottomLeading: 8,
            bottomTrailing: 20,
            topTrailing: 8,
            straightRadius: 12,
            isOrganic: vellumWobble
        )

        VStack(alignment: .leading, spacing: 3) {
            Text("\(citation.index) · \(citation.noteType.rawValue.uppercased())")
                .font(.vellumMono(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(VellumTheme.accentDark)
            Text(citation.noteTitle)
                .font(.vellumSans(15.5, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)
                .lineLimit(1)
            Text("“\(citation.excerpt)”")
                .font(.vellumCaveat(17))
                .foregroundStyle(VellumTheme.muted)
                .lineLimit(1)
        }
        .frame(width: 220, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(VellumTheme.card, in: shape)
        .background {
            shape
                .fill(VellumTheme.ink(0.1))
                .offset(x: 2, y: 3)
        }
        .overlay {
            shape.strokeBorder(VellumTheme.ink(0.28), lineWidth: 1.5)
        }
    }
}

private struct NoteAskSummaryCard: View {
    @Environment(\.vellumWobble) private var vellumWobble
    let summary: String

    var body: some View {
        let shape = VellumOrganicRectangle(
            topLeading: 26,
            bottomLeading: 10,
            bottomTrailing: 28,
            topTrailing: 10,
            straightRadius: 14,
            isOrganic: vellumWobble
        )

        VStack(alignment: .leading, spacing: 8) {
            Label("Summary", systemImage: "text.alignleft")
                .font(.vellumMono(11, weight: .semibold))
                .foregroundStyle(VellumTheme.accentDark)
            Text(summary)
                .font(.vellumSans(18))
                .foregroundStyle(VellumTheme.bodyInk)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(VellumTheme.card, in: shape)
        .background {
            shape
                .fill(VellumTheme.ink(0.1))
                .offset(x: 3, y: 4)
        }
        .overlay {
            shape.strokeBorder(VellumTheme.ink(0.28), lineWidth: 1.5)
        }
    }
}

private struct NoteAskFallbackBanner: View {
    @Environment(\.vellumWobble) private var vellumWobble
    let reason: String

    var body: some View {
        Label(reason, systemImage: "leaf")
            .font(.vellumSans(14.5, weight: .medium))
            .foregroundStyle(VellumTheme.mutedDark)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                VellumTheme.highlight.opacity(0.18),
                in: OrganicPillShape(
                    variant: 1,
                    smallRadius: 9,
                    isOrganic: vellumWobble
                )
            )
            .overlay {
                OrganicPillShape(
                    variant: 1,
                    smallRadius: 9,
                    isOrganic: vellumWobble
                )
                    .strokeBorder(VellumTheme.ink(0.2), lineWidth: 1)
            }
    }
}

private struct NoteAskErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.vellumSans(15.5, italic: true))
            .foregroundStyle(VellumTheme.danger)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct NoteAskEmptyStateRow: View {
    @Environment(\.vellumWobble) private var vellumWobble
    let isStreaming: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("✳")
                        .font(.vellumCaveat(24))
                        .foregroundStyle(VellumTheme.accent)
                }
                Text(isStreaming ? "Summarizing this note…" : "Summarize this note")
                    .font(.vellumSans(17.5, weight: .medium))
                    .foregroundStyle(VellumTheme.ink)
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(VellumTheme.accentDark)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(
                VellumTheme.card,
                in: OrganicPillShape(
                    variant: 0,
                    smallRadius: 12,
                    isOrganic: vellumWobble
                )
            )
            .overlay {
                OrganicPillShape(
                    variant: 0,
                    smallRadius: 12,
                    isOrganic: vellumWobble
                )
                    .strokeBorder(VellumTheme.ink(0.26), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(isStreaming)
    }
}

private struct NoteAskInputBar: View {
    @Environment(\.vellumWobble) private var vellumWobble
    @Binding var text: String
    let isStreaming: Bool
    let onSubmit: () -> Void

    private var isSendDisabled: Bool {
        isStreaming || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let shape = OrganicPillShape(variant: 0, isOrganic: vellumWobble)

        HStack(spacing: 10) {
            TextField("Ask about this note…", text: $text, axis: .vertical)
                .accessibilityIdentifier("note-ask-input")
                .font(.vellumSans(17.5))
                .foregroundStyle(VellumTheme.ink)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VellumTheme.paper)
                    .frame(width: 44, height: 44)
                    .background(VellumTheme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSendDisabled)
            .opacity(isSendDisabled ? 0.38 : 1)
            .accessibilityLabel("Send question")
        }
        .padding(.leading, 18)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(VellumTheme.popover, in: shape)
        .background {
            shape
                .fill(VellumTheme.ink(0.12))
                .offset(x: 4, y: 5)
        }
        .overlay {
            shape.strokeBorder(VellumTheme.ink(0.32), lineWidth: 1.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}
