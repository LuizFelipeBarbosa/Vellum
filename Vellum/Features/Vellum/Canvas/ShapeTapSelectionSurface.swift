import PencilKit
import SwiftUI
import UIKit

@MainActor
struct ShapeTapSelectionSurface: UIViewRepresentable {
    let canvasReference: NoteCanvasReference
    let elementsStore: CanvasElementsStore
    let selectionController: CanvasSelectionController
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            canvasReference: canvasReference,
            elementsStore: elementsStore,
            selectionController: selectionController,
            isEnabled: isEnabled
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.syncInstallation()
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.canvasReference = canvasReference
        context.coordinator.elementsStore = elementsStore
        context.coordinator.selectionController = selectionController
        context.coordinator.isEnabled = isEnabled
        context.coordinator.syncInstallation()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.dismantleInstallation()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canvasReference: NoteCanvasReference
        var elementsStore: CanvasElementsStore
        var selectionController: CanvasSelectionController
        var isEnabled: Bool {
            didSet {
                guard !isEnabled else { return }
                resetTrackedTap()
            }
        }

        let observer = PenDwellObserverGestureRecognizer()
        weak var installedCanvas: PKCanvasView?

        private static let maximumTapMovement: CGFloat = 10
        private static let minimumHitWidth: CGFloat = 4
        private static let touchHitRadius: CGFloat = 12

        private var firstLocation: CGPoint?
        private var lastLocation: CGPoint?
        private var maximumMovement: CGFloat = 0

        init(
            canvasReference: NoteCanvasReference,
            elementsStore: CanvasElementsStore,
            selectionController: CanvasSelectionController,
            isEnabled: Bool
        ) {
            self.canvasReference = canvasReference
            self.elementsStore = elementsStore
            self.selectionController = selectionController
            self.isEnabled = isEnabled
            super.init()

            observer.allowsPencilTouches = false
            observer.allowsDirectTouches = true
            observer.delegate = self
            observer.isEnabled = false
            observer.onStrokeBegan = { [weak self] in
                self?.resetTrackedTap()
            }
            observer.onStrokePoints = { [weak self] points in
                self?.track(points)
            }
            observer.onStrokeEnded = { [weak self] cancelled in
                self?.finishTap(cancelled: cancelled)
            }
        }

        func syncInstallation() {
            guard let canvasView = canvasReference.canvasView else {
                observer.isEnabled = false
                resetTrackedTap()
                return
            }

            if canvasView !== installedCanvas {
                if let installedCanvas {
                    installedCanvas.removeGestureRecognizer(observer)
                }
                canvasView.addGestureRecognizer(observer)
                installedCanvas = canvasView
            }

            let effectiveIsEnabled = isTapSelectionEnabled(on: canvasView)
            observer.isEnabled = effectiveIsEnabled
            if !effectiveIsEnabled {
                resetTrackedTap()
            }
        }

        func dismantleInstallation() {
            if let installedCanvas {
                installedCanvas.removeGestureRecognizer(observer)
            }
            installedCanvas = nil
            resetTrackedTap()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func track(_ points: [TimedPoint]) {
            for point in points {
                if firstLocation == nil {
                    firstLocation = point.location
                }
                lastLocation = point.location

                if let firstLocation {
                    maximumMovement = max(
                        maximumMovement,
                        hypot(
                            point.location.x - firstLocation.x,
                            point.location.y - firstLocation.y
                        )
                    )
                }
            }
        }

        private func finishTap(cancelled: Bool) {
            defer { resetTrackedTap() }
            guard !cancelled,
                  firstLocation != nil,
                  let lastLocation,
                  maximumMovement < Self.maximumTapMovement,
                  let canvasView = observer.view as? PKCanvasView,
                  isTapSelectionEnabled(on: canvasView),
                  canvasView.zoomScale > 0 else {
                return
            }

            let contentPoint = CGPoint(
                x: lastLocation.x / canvasView.zoomScale,
                y: lastLocation.y / canvasView.zoomScale
            )
            if let element = ShapeHitTester.hitTest(
                elements: elementsStore.elements,
                at: contentPoint,
                minimumHitWidth: Self.minimumHitWidth,
                extraRadius: Self.touchHitRadius
            ) {
                selectionController.selectElement(id: element.id)
            } else {
                selectionController.clearSelection()
            }
        }

        private func isTapSelectionEnabled(on canvasView: PKCanvasView) -> Bool {
            isEnabled && canvasView.drawingPolicy == .pencilOnly
        }

        private func resetTrackedTap() {
            firstLocation = nil
            lastLocation = nil
            maximumMovement = 0
        }
    }
}
