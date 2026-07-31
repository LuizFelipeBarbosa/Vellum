import Foundation
import Observation
import SwiftUI
import VellumCore

struct VellumAskView: View {
    @Bindable var model: VellumAppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ASKED ACROSS \(model.noteCount) SOURCES")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.32)
                        .foregroundStyle(VellumTheme.muted)

                    if model.askScreen.phase == .idle {
                        idleContent
                    } else {
                        Text(model.askScreen.question)
                            .font(.vellumNewsreader(28, italic: true))
                            .foregroundStyle(VellumTheme.ink)
                            .padding(.top, 10)

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
                .padding(.top, 44)
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
                .font(.vellumNewsreader(28, italic: true))
                .foregroundStyle(VellumTheme.ink)
                .padding(.top, 10)
            Text("Answers are grounded in your notes, PDFs, decks, and recordings — every claim cites its page.")
                .font(.system(size: 14))
                .foregroundStyle(VellumTheme.muted)
                .padding(.top, 8)
            VStack(spacing: 10) {
                ForEach(Array(model.askScreen.suggested.prefix(3).enumerated()), id: \.offset) { _, suggestion in
                    Button {
                        model.askScreen.ask(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 15))
                            .foregroundStyle(VellumTheme.bodyInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(VellumTheme.card, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(VellumTheme.ink(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 26)
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(message.isEmpty ? "The answer couldn’t be completed. Please try again." : message)
                .font(.vellumNewsreader(16, italic: true))
                .foregroundStyle(VellumTheme.mutedDark)
                .lineSpacing(9.6)
                .padding(.top, 22)
            VellumFollowUpChip(label: "Try again") {
                model.askScreen.ask(model.askScreen.question)
            }
            .padding(.top, 18)
        }
    }

    private var inputArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                TextField(
                    "",
                    text: Binding(
                        get: { model.askScreen.inputText },
                        set: { model.askScreen.inputText = $0 }
                    ),
                    prompt: Text("Follow up…")
                        .font(.vellumNewsreader(16, italic: true))
                        .foregroundStyle(VellumTheme.mutedCount)
                )
                .font(.vellumNewsreader(16, italic: true))
                .foregroundStyle(VellumTheme.ink)
                .textFieldStyle(.plain)
                .onSubmit(submitFreeQuestion)

                Button(action: submitFreeQuestion) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VellumTheme.paper)
                        .frame(width: 36, height: 36)
                        .background(VellumTheme.ink, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(VellumTheme.popover, in: Capsule())
            .overlay(Capsule().stroke(VellumTheme.ink(0.14), lineWidth: 1))
            .shadow(color: VellumTheme.ink(0.08), radius: 8, y: 4)

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

private struct VellumThinkingView: View {
    let sourceCount: Int
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(VellumTheme.accent)
                .frame(width: 8, height: 8)
                .opacity(pulsing ? 1 : 0.35)
            Text("reading \(sourceCount) sources…")
        }
        .font(.vellumNewsreader(15, italic: true))
        .foregroundStyle(VellumTheme.muted)
        .padding(.top, 26)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
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
            VellumFlowLayout(spacing: 0, lineSpacing: 8) {
                ForEach(tokens) { token in
                    if let number = token.citationNumber {
                        Button {
                            guard let citation = answer.citations.first(where: { $0.index == number }) else {
                                return
                            }
                            openCitation(citation)
                        } label: {
                            Text("\(number)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(VellumTheme.accentDark)
                                .frame(width: 17, height: 17)
                                .background(VellumTheme.accent(0.14), in: Circle())
                                .padding(.horizontal, 3)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(token.text)
                            .font(.system(size: 16, weight: token.emphasized ? .semibold : .regular))
                            .foregroundStyle(VellumTheme.bodyInk)
                    }
                }
            }
            .padding(.top, 22)

            if !answer.citations.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(answer.citations) { citation in
                        Button {
                            openCitation(citation)
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(citation.index) · \(citation.noteType.rawValue.uppercased())")
                                    .font(.vellumMono(10, weight: .semibold))
                                    .foregroundStyle(VellumTheme.accent)
                                Text(citation.noteTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(VellumTheme.ink)
                                    .padding(.top, 5)
                                    .lineLimit(1)
                                Text("\"\(citation.excerpt)\"")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(VellumTheme.muted)
                                    .padding(.top, 2)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(VellumTheme.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(VellumTheme.ink(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    if answer.citations.count == 1 { Spacer() }
                }
                .padding(.top, 26)
            }

            if !answer.followUps.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(answer.followUps.enumerated()), id: \.offset) { _, followUp in
                        VellumFollowUpChip(label: followUp) {
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

private struct VellumFollowUpChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(VellumTheme.bodyMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(Capsule().stroke(VellumTheme.ink(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
