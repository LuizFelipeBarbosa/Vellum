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
        List {
            if events.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "clock",
                    description: Text("Changes and analysis actions will appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: symbol(for: event.kind))
                            .foregroundStyle(.tint)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.message)
                            Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
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

    private func symbol(for kind: ActivityKind) -> String {
        switch kind {
        case .noteCreated: "doc.badge.plus"
        case .noteUpdated: "square.and.pencil"
        case .noteDeleted: "trash"
        case .noteTrashed: "trash"
        case .noteRestored: "arrow.uturn.backward.circle"
        case .notePurged: "trash.slash"
        case .analysisRequested: "sparkles"
        case .proposalAccepted: "checkmark.circle"
        case .proposalRejected: "xmark.circle"
        case .proposalMarkedStale: "clock.badge.exclamationmark"
        case .noteFiledToSpace: "folder"
        case .notesLinked: "link"
        case .taskExtracted: "checklist"
        case .taskCompleted: "checkmark.square"
        case .entityExtracted: "person.text.rectangle"
        case .spaceCreated: "folder.badge.plus"
        case .spaceDeleted: "folder.badge.minus"
        case .questionAnswered: "questionmark.bubble"
        case .workspaceSeeded: "shippingbox"
        case .unknown: "questionmark.circle"
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
