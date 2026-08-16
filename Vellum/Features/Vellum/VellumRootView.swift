import os
import SwiftUI
import UIKit

@MainActor
private final class BackgroundTaskAssertion {
    private var taskID: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        taskID = UIApplication.shared.beginBackgroundTask(
            withName: "com.vellum.flushSave"
        ) { [weak self] in
            self?.endIfNeeded()
        }
    }

    func endIfNeeded() {
        guard taskID != .invalid else { return }
        let taskIDToEnd = taskID
        taskID = .invalid
        UIApplication.shared.endBackgroundTask(taskIDToEnd)
    }
}

struct VellumRootView: View {
    private static let saveLogger = Logger(subsystem: "com.vellum", category: "save")

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
                    case .today:
                        VellumTodayView(model: model)
                    case .note:
                        NoteSplitContainerView(app: model)
                    case .graph:
                        VellumGraphView(model: model)
                    case .tasks:
                        VellumTasksView(model: model)
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

            VellumGrainOverlay()

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
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .environment(\.vellumGrain, model.feelGrain)
        .environment(\.vellumHandwritingPreviews, model.feelHandwriting)
        .environment(\.vellumWobble, model.feelWobble)
        .foregroundStyle(VellumTheme.ink)
        .tint(VellumTheme.accentDark)
        .task { await model.bootstrap() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                Task { @MainActor in
                    let backgroundTask = BackgroundTaskAssertion()
                    backgroundTask.begin()
                    let didFlushAll = await model.split.flushAll()
                    backgroundTask.endIfNeeded()
                    if !didFlushAll {
                        Self.saveLogger.error(
                            "background flush did not save all panes"
                        )
                    }
                }
            }
            if newPhase == .background {
                model.toolPreferences.flush()
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
