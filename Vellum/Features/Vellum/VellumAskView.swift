import Foundation
import SwiftUI
import VellumCore

struct VellumAskView: View {
    @Environment(\.vellumWobble) private var vellumWobble
    @Bindable var model: VellumAppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Text("ASKED ACROSS \(model.noteCount) SOURCES")
                            .font(.vellumMono(11))
                            .tracking(1.5)
                            .foregroundStyle(VellumTheme.muted)

                        VellumDashedRule()
                            .stroke(
                                VellumTheme.ink(0.2),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
                            )
                            .frame(height: 1.5)
                    }

                    if model.askScreen.phase == .idle {
                        idleContent
                    } else {
                        Text(model.askScreen.question)
                            .font(.vellumSans(34, italic: true))
                            .foregroundStyle(VellumTheme.ink)
                            .lineSpacing(8.5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)

                        if model.askScreen.phase == .thinking {
                            VellumThinkingView(sourceCount: model.noteCount)
                        } else if let answer = model.askScreen.answer {
                            VellumAnswerView(answer: answer, model: model)
                        } else if let errorMessage = model.askScreen.errorMessage {
                            errorContent(errorMessage)
                        }
                    }

                    Spacer(minLength: 26)
                    inputArea
                }
                .frame(minHeight: 740, alignment: .top)
                .padding(.top, 38)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .frame(width: 660)
            .frame(maxWidth: .infinity)
        }
        .background(VellumTheme.paper)
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What would you like to know?")
                .font(.vellumSans(34, italic: true))
                .foregroundStyle(VellumTheme.ink)
                .lineSpacing(8.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Text("Answers are grounded in your notes, PDFs, decks, and recordings — every claim cites its page.")
                .font(.vellumSans(17))
                .foregroundStyle(VellumTheme.mutedDark)
                .lineSpacing(8.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            VStack(spacing: 11) {
                ForEach(Array(model.askScreen.suggested.prefix(3).enumerated()), id: \.offset) { _, suggestion in
                    VellumSuggestionCard(suggestion: suggestion) {
                        model.askScreen.ask(suggestion)
                    }
                }
            }
            .padding(.top, 24)
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(message.isEmpty ? "The answer couldn’t be completed. Please try again." : message)
                .font(.vellumSans(19, italic: true))
                .foregroundStyle(VellumTheme.mutedDark)
                .lineSpacing(10)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
            Button {
                model.askScreen.ask(model.askScreen.question)
            } label: {
                Text("Try again")
                    .font(.vellumSans(16.5, weight: .semibold))
            }
            .buttonStyle(VellumPillButtonStyle(.outline))
            .padding(.top, 18)
        }
    }

    private var inputArea: some View {
        let shape = OrganicPillShape(variant: 0, isOrganic: vellumWobble)

        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                TextField(
                    "",
                    text: Binding(
                        get: { model.askScreen.inputText },
                        set: { model.askScreen.inputText = $0 }
                    ),
                    prompt: Text("ask anything…")
                        .font(.vellumSans(19, italic: true))
                        .foregroundStyle(VellumTheme.muted)
                )
                .font(.vellumSans(19, italic: true))
                .foregroundStyle(VellumTheme.ink)
                .textFieldStyle(.plain)
                .onSubmit(submitFreeQuestion)

                Button(action: submitFreeQuestion) {
                    ZStack {
                        VellumBlobDot(color: VellumTheme.ink, size: 54)
                        Text("↑")
                            .font(.vellumSans(22, weight: .semibold))
                            .foregroundStyle(VellumTheme.paper)
                    }
                    .frame(width: 54, height: 54)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 22)
            .padding(.trailing, 9)
            .padding(.vertical, 9)
            .background(VellumTheme.popover, in: shape)
            .background {
                shape
                    .fill(VellumTheme.ink(0.12))
                    .offset(x: 4, y: 5)
            }
            .overlay {
                shape.strokeBorder(VellumTheme.ink(0.32), lineWidth: 1.5)
            }

            Text(footerText)
                .font(.vellumMono(11))
                .foregroundStyle(VellumTheme.mutedCount)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 26)
    }

    private var footerText: String {
        guard model.askScreen.phase == .answered,
              let answer = model.askScreen.answer else {
            return "answers stay on-device · every claim cites its page"
        }
        let duration = model.askScreen.answeredIn ?? 0
        return "answered on-device · \(answer.citations.count) sources · \(String(format: "%.1f", duration))s"
    }

    private func submitFreeQuestion() {
        let trimmed = model.askScreen.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.askScreen.ask(trimmed)
    }
}

private struct VellumSuggestionCard: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let suggestion: String
    let action: () -> Void

    var body: some View {
        let shape = VellumOrganicRectangle(
            topLeading: 26,
            bottomLeading: 10,
            bottomTrailing: 28,
            topTrailing: 10,
            straightRadius: 14,
            isOrganic: vellumWobble
        )

        Button(action: action) {
            HStack(spacing: 14) {
                Text("?")
                    .font(.vellumCaveat(26))
                    .foregroundStyle(VellumTheme.accent)

                Text(suggestion)
                    .font(.vellumSans(18))
                    .foregroundStyle(VellumTheme.bodyInk)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("→")
                    .font(.vellumSans(20))
                    .foregroundStyle(VellumTheme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(VellumTheme.card, in: shape)
            .background {
                shape
                    .fill(VellumTheme.ink(0.1))
                    .offset(x: 3, y: 4)
            }
            .overlay {
                shape.strokeBorder(VellumTheme.ink(0.3), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct VellumThinkingView: View {
    let sourceCount: Int
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 11) {
            VellumBlobDot(color: VellumTheme.accent, size: 11)
                .scaleEffect(pulsing ? 1 : 0.82)
                .opacity(pulsing ? 1 : 0.4)
            Text("reading \(sourceCount) sources…")
        }
        .font(.vellumSans(19, italic: true))
        .foregroundStyle(VellumTheme.muted)
        .padding(.top, 26)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

private struct VellumAnswerView: View {
    let answer: AskAnswer
    @Bindable var model: VellumAppModel

    private var tokens: [VellumAnswerToken] {
        var result: [VellumAnswerToken] = []
        var index = 0
        for segment in answer.segments {
            switch segment {
            case .citation(let citationIndex):
                result.append(.init(
                    id: index,
                    text: "",
                    emphasized: false,
                    citationNumber: citationIndex
                ))
                index += 1
            case .text(let text, let emphasized):
                let pieces = text.split(separator: " ", omittingEmptySubsequences: false)
                for (pieceIndex, piece) in pieces.enumerated() {
                    var text = String(piece)
                    if pieceIndex < pieces.count - 1 { text += " " }
                    if !text.isEmpty {
                        result.append(.init(
                            id: index,
                            text: text,
                            emphasized: emphasized,
                            citationNumber: nil
                        ))
                        index += 1
                    }
                }
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VellumFlowLayout(spacing: 0, lineSpacing: 11) {
                ForEach(tokens) { token in
                    if let number = token.citationNumber {
                        Button {
                            guard let citation = answer.citations.first(where: { $0.index == number }) else {
                                return
                            }
                            openCitation(citation)
                        } label: {
                            Text("\(number)")
                                .font(.vellumMono(11, weight: .semibold))
                                .foregroundStyle(VellumTheme.accentDark)
                                .frame(width: 22, height: 22)
                                .background(VellumTheme.accent(0.16), in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(VellumTheme.accent(0.5), lineWidth: 1.5)
                                }
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                    } else {
                        VellumAnswerTextToken(token: token)
                    }
                }
            }
            .padding(.top, 22)

            if !answer.citations.isEmpty {
                HStack(alignment: .top, spacing: 11) {
                    ForEach(answer.citations) { citation in
                        Button {
                            openCitation(citation)
                        } label: {
                            VellumCitationCard(citation: citation)
                        }
                        .buttonStyle(.plain)
                    }
                    if answer.citations.count == 1 { Spacer() }
                }
                .padding(.top, 24)
            }

            if !answer.followUps.isEmpty {
                VellumFlowLayout(spacing: 9, lineSpacing: 9) {
                    ForEach(Array(answer.followUps.enumerated()), id: \.offset) { index, followUp in
                        VellumFollowUpChip(label: followUp, variant: index % 4) {
                            model.askScreen.ask(followUp)
                        }
                    }
                }
                .padding(.top, 22)
            }
        }
        .transition(.offset(y: 6).combined(with: .opacity))
    }

    private func openCitation(_ citation: Citation) {
        Task {
            await model.split.flushAll()
            await model.openNote(citation.noteID)
        }
    }
}

private struct VellumAnswerToken: Identifiable {
    let id: Int
    let text: String
    let emphasized: Bool
    let citationNumber: Int?
}

private struct VellumAnswerTextToken: View {
    let token: VellumAnswerToken

    var body: some View {
        Text(token.text)
            .font(.vellumSans(19.5, weight: token.emphasized ? .semibold : .regular))
            .foregroundStyle(VellumTheme.bodyInk)
            .background(alignment: .bottom) {
                if token.emphasized {
                    Rectangle()
                        .fill(VellumTheme.highlight.opacity(0.55))
                        .frame(height: 8)
                }
            }
    }
}

private struct VellumCitationCard: View {
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

        VStack(alignment: .leading, spacing: 0) {
            Text("\(citation.index) · \(citation.noteType.rawValue.uppercased())")
                .font(.vellumMono(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(VellumTheme.accentDark)
            Text(citation.noteTitle)
                .font(.vellumSans(16, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)
                .padding(.top, 5)
                .lineLimit(1)
            Text("\"\(citation.excerpt)\"")
                .font(.vellumCaveat(17))
                .foregroundStyle(VellumTheme.muted)
                .padding(.top, 2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
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

private struct VellumFollowUpChip: View {
    @Environment(\.vellumWobble) private var vellumWobble

    let label: String
    let variant: Int
    let action: () -> Void

    var body: some View {
        let shape = OrganicPillShape(variant: variant, isOrganic: vellumWobble)

        Button(action: action) {
            Text(label)
                .font(.vellumSans(16.5))
                .foregroundStyle(VellumTheme.bodyMuted)
                .padding(.horizontal, 19)
                .frame(minHeight: 48)
                .background(VellumTheme.field, in: shape)
                .overlay {
                    shape.strokeBorder(VellumTheme.ink(0.32), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
    }
}
