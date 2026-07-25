import Foundation
import PencilKit
import SwiftUI
import UIKit
import VellumCore

@MainActor
struct ShapeEraserSurface: UIViewRepresentable {
    let canvasReference: NoteCanvasReference
    let elementsStore: CanvasElementsStore
    let eraserConfig: EraserConfig
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            canvasReference: canvasReference,
            elementsStore: elementsStore,
            eraserConfig: eraserConfig,
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
        context.coordinator.eraserConfig = eraserConfig
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
        var eraserConfig: EraserConfig
        var isEnabled: Bool {
            didSet {
                guard !isEnabled else { return }
                finishDrag()
            }
        }

        let observer = PenDwellObserverGestureRecognizer()
        weak var installedCanvas: PKCanvasView?

        private static let minimumHitWidth: CGFloat = 4
        // Vector erasers have no configured width, so use a modest fixed content-space radius.
        private static let wholeStrokeEraserRadius: CGFloat = 12

        /// Elements as they were when the drag began, so the whole gesture collapses
        /// into a single undo step even though shapes are removed on contact.
        private var elementsAtDragStart: [CanvasElement]?
        private var didEraseDuringDrag = false
        private var previousSamplePoint: CGPoint?

        init(
            canvasReference: NoteCanvasReference,
            elementsStore: CanvasElementsStore,
            eraserConfig: EraserConfig,
            isEnabled: Bool
        ) {
            self.canvasReference = canvasReference
            self.elementsStore = elementsStore
            self.eraserConfig = eraserConfig
            self.isEnabled = isEnabled
            super.init()

            observer.allowsPencilTouches = true
#if targetEnvironment(simulator)
            #if DEBUG
            observer.allowsDirectTouches = !ProcessInfo.processInfo.arguments.contains(
                "-vellum-force-pencil-only"
            )
            #else
            observer.allowsDirectTouches = true
            #endif
#else
            observer.allowsDirectTouches = false
#endif
            observer.delegate = self
            observer.isEnabled = isEnabled
            observer.onStrokeBegan = { [weak self] in
                self?.dragBegan()
            }
            observer.onStrokePoints = { [weak self] points in
                self?.sample(points)
            }
            observer.onStrokeEnded = { [weak self] _ in
                self?.dragEnded()
            }
        }

        func syncInstallation() {
            observer.isEnabled = isEnabled

            guard let canvasView = canvasReference.canvasView,
                  canvasView !== installedCanvas else { return }

            if let installedCanvas {
                installedCanvas.removeGestureRecognizer(observer)
            }
            canvasView.addGestureRecognizer(observer)
            installedCanvas = canvasView
        }

        func dismantleInstallation() {
            if let installedCanvas {
                installedCanvas.removeGestureRecognizer(observer)
            }
            installedCanvas = nil
            finishDrag()
        }

        func dragBegan() {
            finishDrag()
            guard isEnabled else { return }
            elementsAtDragStart = elementsStore.elements
        }

        func dragSample(at contentPoint: CGPoint) {
            guard isEnabled,
                  elementsAtDragStart != nil,
                  contentPoint.x.isFinite,
                  contentPoint.y.isFinite else {
                return
            }

            let segmentStart = previousSamplePoint
            let interpolationCount: Int
            if let segmentStart {
                let segmentLength = hypot(
                    contentPoint.x - segmentStart.x,
                    contentPoint.y - segmentStart.y
                )
                let spacing = max(eraserRadius, Self.minimumHitWidth)
                interpolationCount = max(1, Int(ceil(segmentLength / spacing)))
            } else {
                interpolationCount = 1
            }
            previousSamplePoint = contentPoint

            var hitShapeIDs: [UUID] = []
            for element in elementsStore.elements {
                guard let strokedPath = ShapeHitTester.strokedPath(
                    for: element,
                    minimumHitWidth: Self.minimumHitWidth,
                    extraRadius: eraserRadius
                ) else {
                    continue
                }
                for index in 1...interpolationCount {
                    let samplePoint: CGPoint
                    if let segmentStart {
                        let fraction = CGFloat(index) / CGFloat(interpolationCount)
                        samplePoint = CGPoint(
                            x: segmentStart.x + (contentPoint.x - segmentStart.x) * fraction,
                            y: segmentStart.y + (contentPoint.y - segmentStart.y) * fraction
                        )
                    } else {
                        samplePoint = contentPoint
                    }
                    if strokedPath.contains(samplePoint) {
                        hitShapeIDs.append(element.id)
                        break
                    }
                }
            }

            // Remove on contact so the shape disappears under the pen tip, not on lift.
            // Undo for the whole gesture is registered once, in finishDrag().
            guard !hitShapeIDs.isEmpty else { return }
            didEraseDuringDrag = true
            for id in hitShapeIDs {
                elementsStore.removeElementLive(id: id)
            }
        }

        func tap(at contentPoint: CGPoint) {
            guard isEnabled,
                  contentPoint.x.isFinite,
                  contentPoint.y.isFinite else {
                return
            }

            let tappedShapeIDs: Set<UUID> = Set(
                elementsStore.elements.compactMap { element in
                    guard ShapeHitTester.strokedPath(
                        for: element,
                        minimumHitWidth: Self.minimumHitWidth,
                        extraRadius: eraserRadius
                    )?.contains(contentPoint) == true else {
                        return nil
                    }
                    return element.id
                }
            )
            guard !tappedShapeIDs.isEmpty else { return }

            elementsStore.performTransaction("Erase Shapes") {
                for id in tappedShapeIDs {
                    elementsStore.removeElement(id: id)
                }
            }
        }

        func dragEnded() {
            finishDrag()
        }

        /// Close out an in-flight drag, registering one undo step for everything it erased.
        /// Also runs when the eraser is deselected or torn down mid-drag — the removals have
        /// already been applied live, so the undo entry must be registered regardless.
        private func finishDrag() {
            previousSamplePoint = nil
            defer {
                elementsAtDragStart = nil
                didEraseDuringDrag = false
            }
            guard didEraseDuringDrag, let elementsAtDragStart else { return }
            elementsStore.registerEditingSessionUndo(
                from: elementsAtDragStart,
                label: "Erase Shapes"
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private var eraserRadius: CGFloat {
            switch eraserConfig.mode {
            case .partial:
                CGFloat(eraserConfig.width) / 2
            case .wholeStroke:
                Self.wholeStrokeEraserRadius
            }
        }

        private func sample(_ points: [TimedPoint]) {
            guard let canvasView = observer.view as? PKCanvasView else { return }
            for point in points {
                guard let location = contentLocation(
                    of: point.location,
                    in: canvasView
                ) else { continue }
                dragSample(at: location)
            }
        }

        private func contentLocation(
            of location: CGPoint,
            in canvasView: PKCanvasView
        ) -> CGPoint? {
            guard canvasView.zoomScale > 0 else { return nil }
            return CGPoint(
                x: location.x / canvasView.zoomScale,
                y: location.y / canvasView.zoomScale
            )
        }
    }
}
