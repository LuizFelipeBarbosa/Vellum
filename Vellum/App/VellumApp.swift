import Foundation
import SwiftUI

@main
@MainActor
struct VellumApp: App {
    private let container: AppContainer

    init() {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let workspaceDirectory = documentsDirectory.appendingPathComponent(
            "Workspace",
            isDirectory: true
        )
        container = AppContainer.live(rootDirectory: workspaceDirectory)
    }

    var body: some Scene {
        WindowGroup {
            VellumRootView(
                model: VellumAppModel(
                    container: container,
                    arguments: ProcessInfo.processInfo.arguments
                )
            )
        }
    }
}
