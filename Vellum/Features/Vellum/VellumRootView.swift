import Observation
import SwiftUI

struct VellumRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: VellumAppModel

    init(model: VellumAppModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VellumTheme.paper.ignoresSafeArea()

            HStack(spacing: 0) {
                if showsSidebar {
                    VellumSidebarView(model: model)
                        .frame(width: 264)
                        .transition(.opacity)
                }

                Group {
                    switch model.screen {
                    case .library:
                        VellumLibraryView(model: model)
                    case .note:
                        if let noteModel = model.currentNote {
                            NoteScreenView(model: noteModel, app: model)
                        } else {
                            ProgressView("Loading note…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    case .graph:
                        VellumGraphView(model: model)
                    case .ask:
                        VellumAskView(model: model)
                    case .trash:
                        VellumTrashView(model: model)
                    }
                }
                .id(model.screen)
                .transition(.asymmetric(
                    insertion: .offset(y: 6).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            if let toast = model.toast {
                HStack(spacing: 14) {
                    Text(toast.text)
                    if let actionLabel = toast.actionLabel {
                        Button(actionLabel) {
                            toast.action?()
                            model.toast = nil
                        }
                        .fontWeight(.semibold)
                        .buttonStyle(.plain)
                    }
                }
                    .font(.system(size: 13))
                    .foregroundStyle(VellumTheme.paper)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(VellumTheme.ink, in: Capsule())
                    .shadow(color: VellumTheme.ink(0.3), radius: 12, y: 8)
                    .padding(.bottom, 26)
                    .transition(.offset(y: 8).combined(with: .opacity))
                    .zIndex(50)
            }
        }
        .foregroundStyle(VellumTheme.ink)
        .tint(VellumTheme.accentDark)
        .task { await model.bootstrap() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                Task { await model.currentNote?.flushPendingSave() }
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.screen)
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }

    private var showsSidebar: Bool {
        if case .note = model.screen {
            return false
        }
        return true
    }
}
