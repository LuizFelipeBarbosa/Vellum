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
        // Coalesced Pencil touches arrive ~240x a second; beyond this many points per segment the
        // samples are packed tighter than the eraser can distinguish and only cost time.
        private static let maximumSamplesPerSegment = 64

        /// Elements as they were when the drag began, so the whole gesture collapses
        /// into a single undo step even though shapes are removed on contact.
        private var elementsAtDragStart: [CanvasElement]?
        private var didEraseDuringDrag = false
        private var previousSamplePoint: CGPoint?

        /// Stroked hit paths reused for the length of one drag: stroking is by far the most
        /// expensive part of a sample and a shape's geometry cannot change while it is being
        /// erased. Scoped to the radius it was stroked with, and dropped when the drag ends.
        private var strokedPathCache: [UUID: CGPath] = [:]
        private var strokedPathCacheRadius: CGFloat?

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

            let radius = eraserRadius
            if strokedPathCacheRadius != radius {
                // A width change mid-drag makes every cached path the wrong size.
                strokedPathCache.removeAll()
                strokedPathCacheRadius = radius
            }

            let segmentStart = previousSamplePoint ?? contentPoint
            previousSamplePoint = contentPoint
            let samplePoints = Self.samplePoints(
                from: segmentStart,
                to: contentPoint,
                spacing: max(radius, Self.minimumHitWidth)
            )
            let segmentBounds = Self.boundingBox(from: segmentStart, to: contentPoint)

            var hitShapeIDs: [UUID] = []
            for element in elementsStore.elements {
                let hitBounds = ShapeHitTester.hitBounds(
                    for: element,
                    minimumHitWidth: Self.minimumHitWidth,
                    extraRadius: radius
                )
                // Reject shapes the segment cannot reach before stroking anything: on a busy page
                // almost every element fails here, and this runs once per coalesced touch.
                guard let hitBounds,
                      Self.boundsOverlap(hitBounds, segmentBounds),
                      let strokedPath = strokedHitPath(for: element, radius: radius) else {
                    continue
                }
                if samplePoints.contains(where: { strokedPath.contains($0) }) {
                    hitShapeIDs.append(element.id)
                }
            }

            // Remove on contact so the shape disappears under the pen tip, not on lift.
            // Undo for the whole gesture is registered once, in finishDrag().
            guard !hitShapeIDs.isEmpty else { return }
            didEraseDuringDrag = true
            for id in hitShapeIDs {
                elementsStore.removeElementLive(id: id)
                strokedPathCache.removeValue(forKey: id)
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
            strokedPathCache.removeAll()
            strokedPathCacheRadius = nil
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

        private func strokedHitPath(for element: CanvasElement, radius: CGFloat) -> CGPath? {
            if let cached = strokedPathCache[element.id] { return cached }
            guard let strokedPath = ShapeHitTester.strokedPath(
                for: element,
                minimumHitWidth: Self.minimumHitWidth,
                extraRadius: radius
            ) else {
                return nil
            }
            strokedPathCache[element.id] = strokedPath
            return strokedPath
        }

        /// Points to test along the swipe since the previous sample, so a fast stroke cannot jump
        /// clean over a thin shape between two coalesced touches. The endpoint is always included.
        private static func samplePoints(
            from start: CGPoint,
            to end: CGPoint,
            spacing: CGFloat
        ) -> [CGPoint] {
            let length = hypot(end.x - start.x, end.y - start.y)
            let count = min(
                max(1, Int(ceil(length / spacing))),
                maximumSamplesPerSegment
            )
            return (1...count).map { index in
                let fraction = CGFloat(index) / CGFloat(count)
                return CGPoint(
                    x: start.x + (end.x - start.x) * fraction,
                    y: start.y + (end.y - start.y) * fraction
                )
            }
        }

        private static func boundingBox(from start: CGPoint, to end: CGPoint) -> CGRect {
            CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        }

        /// `CGRect.intersects` treats a zero-area rect as empty and always answers false, and a
        /// straight or stationary swipe produces exactly that, so compare the edges directly.
        private static func boundsOverlap(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
            lhs.minX <= rhs.maxX && rhs.minX <= lhs.maxX
                && lhs.minY <= rhs.maxY && rhs.minY <= lhs.maxY
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
