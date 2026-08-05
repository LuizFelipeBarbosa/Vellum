import Foundation
import SwiftUI
import VellumCore

@MainActor
struct ActivityView: View {
    let workspace: WorkspaceService
    let noteID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var events: [ActivityEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            VellumSheetCard(title: "What Vellum did", onDone: { dismiss() }) {
                activityContent
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .presentationBackground(.clear)
        .task {
            await loadActivity()
        }
        .alert(
            "Vellum",
            isPresented: errorBinding,
            actions: {
                Button("OK", role: .cancel) { errorMessage = nil }
            },
            message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        )
    }

    @ViewBuilder
    private var activityContent: some View {
        if events.isEmpty && !isLoading {
            Text("No marks yet — Vellum’s activity will appear here.")
                .font(.vellumCaveat(20))
                .foregroundStyle(VellumTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        } else {
            ScrollView {
                if !events.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            ActivityEventRow(
                                event: event,
                                color: color(for: event.kind)
                            )

                            if index < events.count - 1 {
                                VellumDashedRule()
                                    .stroke(
                                        VellumTheme.ink(0.14),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
                                    )
                                    .frame(height: 1.5)
                            }
                        }

                        Text("nothing happens without leaving a mark")
                            .font(.vellumCaveat(20))
                            .foregroundStyle(VellumTheme.mutedCount)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func loadActivity() async {
        isLoading = true
        defer { isLoading = false }

        do {
            events = try await workspace.activity(noteID: noteID).sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func color(for kind: ActivityKind) -> Color {
        switch kind {
        case .noteFiledToSpace, .spaceCreated, .spaceDeleted:
            VellumTheme.spaceTeal
        case .notesLinked, .questionAnswered:
            VellumTheme.highlight
        case .entityExtracted, .noteCreated, .noteUpdated, .noteRestored, .workspaceSeeded:
            VellumTheme.spaceGreen
        case .taskExtracted, .taskCompleted, .proposalAccepted, .proposalRejected,
             .proposalMarkedStale, .analysisRequested:
            VellumTheme.accent
        case .noteDeleted, .noteTrashed, .notePurged, .unknown:
            VellumTheme.muted
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        )
    }
}

private struct ActivityEventRow: View {
    let event: ActivityEvent
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VellumBlobDot(color: color, size: 10)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.message)
                    .font(.vellumSans(17))
                    .foregroundStyle(VellumTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(event.createdAt, style: .relative)
                    .font(.vellumMono(11))
                    .foregroundStyle(VellumTheme.muted)
            }
        }
        .padding(.vertical, 13)
    }
}
