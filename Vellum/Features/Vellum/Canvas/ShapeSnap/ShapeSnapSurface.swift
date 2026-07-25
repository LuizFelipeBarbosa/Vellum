import Foundation
import PencilKit
import SwiftUI
import UIKit

@MainActor
struct ShapeSnapSurface: UIViewRepresentable {
    let controller: ShapeSnapController
    let isEnabled: Bool
    let inkConfig: InkToolConfig?
    let isDrawingEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        applyConfiguration(to: controller)
        context.coordinator.controller = controller
        context.coordinator.syncInstallation()
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        applyConfiguration(to: controller)
        context.coordinator.controller = controller
        context.coordinator.syncInstallation()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.dismantleInstallation()
    }

    private func applyConfiguration(to controller: ShapeSnapController) {
        controller.isEnabled = isEnabled
        controller.activeInkConfig = inkConfig
        controller.isDrawingEnabled = isDrawingEnabled
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var controller: ShapeSnapController
        let recognizer = PenDwellObserverGestureRecognizer()
        weak var installedCanvas: PKCanvasView?

        init(controller: ShapeSnapController) {
            self.controller = controller
            super.init()

            recognizer.delegate = self
            recognizer.onStrokeBegan = { [weak self] in
                self?.controller.strokeBegan()
            }
            recognizer.onStrokePoints = { [weak self] points in
                self?.controller.strokeContinued(points: points)
            }
            recognizer.onStrokeEnded = { [weak self] cancelled in
                self?.controller.strokeEnded(cancelled: cancelled)
            }
        }

        func syncInstallation() {
#if targetEnvironment(simulator)
            #if DEBUG
            recognizer.allowsDirectTouches = !ProcessInfo.processInfo.arguments.contains(
                "-vellum-force-pencil-only"
            )
            #else
            recognizer.allowsDirectTouches = true
            #endif
#else
            recognizer.allowsDirectTouches = false
#endif

            guard let canvasView = controller.canvasReference?.canvasView,
                  canvasView !== installedCanvas else {
                return
            }

            if let installedCanvas {
                installedCanvas.removeGestureRecognizer(recognizer)
            }
            canvasView.addGestureRecognizer(recognizer)
            installedCanvas = canvasView
        }

        func dismantleInstallation() {
            controller.strokeEnded(cancelled: true)
            if let installedCanvas {
                installedCanvas.removeGestureRecognizer(recognizer)
            }
            installedCanvas = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
