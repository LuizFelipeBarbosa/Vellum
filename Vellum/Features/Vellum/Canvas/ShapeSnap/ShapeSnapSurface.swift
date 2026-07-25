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

        private var isStrokeInFlight = false

        init(controller: ShapeSnapController) {
            self.controller = controller
            super.init()

            recognizer.delegate = self
            recognizer.isEnabled = false
            recognizer.onStrokeBegan = { [weak self] in
                guard let self else { return }
                isStrokeInFlight = true
                controller.strokeBegan()
            }
            recognizer.onStrokePoints = { [weak self] points in
                self?.controller.strokeContinued(points: points)
            }
            recognizer.onStrokeEnded = { [weak self] cancelled in
                guard let self else { return }
                controller.strokeEnded(cancelled: cancelled)
                isStrokeInFlight = false
                applyEnabledState()
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

            guard let canvasView = controller.canvasReference?.canvasView else { return }

            if canvasView !== installedCanvas {
                if let installedCanvas {
                    installedCanvas.removeGestureRecognizer(recognizer)
                }
                canvasView.addGestureRecognizer(recognizer)
                installedCanvas = canvasView
                // A stroke tracked on the canvas we just left can never report its
                // end here, so it must not hold the enabled state hostage.
                isStrokeInFlight = false
            }

            applyEnabledState()
        }

        func dismantleInstallation() {
            controller.strokeEnded(cancelled: true)
            isStrokeInFlight = false
            if let installedCanvas {
                installedCanvas.removeGestureRecognizer(recognizer)
            }
            installedCanvas = nil
        }

        /// Keeps the recognizer off under the tools that do not snap shapes, so it
        /// stops seeing every touch instead of relying on the controller's guards.
        ///
        /// Deferred while a stroke is in flight: disabling a gesture recognizer
        /// mid-touch cancels it without delivering `touchesEnded`/`touchesCancelled`,
        /// so `strokeEnded` would never run — and that is the only place that commits
        /// a live line adjustment and re-enables PencilKit's drawing recognizer.
        /// Switching tools mid-stroke therefore takes effect on the next pen lift;
        /// until then `controller.isEnabled` is already false, so nothing is captured
        /// or recognized in the meantime.
        private func applyEnabledState() {
            guard !isStrokeInFlight else { return }
            recognizer.isEnabled = controller.isEnabled
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
