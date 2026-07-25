import Foundation
import PencilKit
import SwiftUI
import UIKit
import VellumCore

@MainActor
struct SelectionCaptureSurface: UIViewRepresentable {
    let controller: CanvasSelectionController
    let selectionMode: SelectionMode
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            controller: controller,
            selectionMode: selectionMode,
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
        context.coordinator.controller = controller
        context.coordinator.selectionMode = selectionMode
        context.coordinator.isEnabled = isEnabled
        context.coordinator.syncInstallation()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.dismantleInstallation()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var controller: CanvasSelectionController
        var selectionMode: SelectionMode
        var isEnabled: Bool {
            didSet {
                guard oldValue, !isEnabled else { return }
                invalidateAutoScroll(clearDragLocation: true)
                activeDragIntent = nil
                claimedDragIntent = nil
                dragStartLocation = nil
                resetPinchClaimDecision()
            }
        }
        let panGestureRecognizer = UIPanGestureRecognizer()
        let tapGestureRecognizer = UITapGestureRecognizer()
        let pinchGestureRecognizer = UIPinchGestureRecognizer()
        weak var installedCanvas: PKCanvasView?

        /// Decided when the pan recognizer claims a touch; promoted to `activeDragIntent`
        /// once the pan actually begins.
        private var claimedDragIntent: SelectionDragIntent?
        private var activeDragIntent: SelectionDragIntent?
        private var dragStartLocation: CGPoint?
        private var pinchClaimDecision: Bool?
        private weak var pinchDecisionTouch: UITouch?
        private var autoScrollDisplayLink: CADisplayLink?
        private var lastDragScreenLocation: CGPoint?

        init(
            controller: CanvasSelectionController,
            selectionMode: SelectionMode,
            isEnabled: Bool
        ) {
            self.controller = controller
            self.selectionMode = selectionMode
            self.isEnabled = isEnabled
            super.init()

            panGestureRecognizer.maximumNumberOfTouches = 1
            panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
            panGestureRecognizer.delegate = self
            tapGestureRecognizer.addTarget(self, action: #selector(handleTap(_:)))
            pinchGestureRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
            pinchGestureRecognizer.delegate = self
        }

        func syncInstallation() {
            panGestureRecognizer.isEnabled = isEnabled
            tapGestureRecognizer.isEnabled = isEnabled
            pinchGestureRecognizer.isEnabled = isEnabled

            guard let canvasView = controller.canvasReference?.canvasView,
                  canvasView !== installedCanvas else { return }

            invalidateAutoScroll(clearDragLocation: true)
            if let installedCanvas {
                installedCanvas.removeGestureRecognizer(panGestureRecognizer)
                installedCanvas.removeGestureRecognizer(tapGestureRecognizer)
                installedCanvas.removeGestureRecognizer(pinchGestureRecognizer)
            }
            canvasView.addGestureRecognizer(panGestureRecognizer)
            canvasView.addGestureRecognizer(tapGestureRecognizer)
            canvasView.addGestureRecognizer(pinchGestureRecognizer)
            installedCanvas = canvasView
            resetPinchClaimDecision()
        }

        func dismantleInstallation() {
            invalidateAutoScroll(clearDragLocation: true)
            if let installedCanvas {
                installedCanvas.removeGestureRecognizer(panGestureRecognizer)
                installedCanvas.removeGestureRecognizer(tapGestureRecognizer)
                installedCanvas.removeGestureRecognizer(pinchGestureRecognizer)
            }
            installedCanvas = nil
            resetPinchClaimDecision()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            if gestureRecognizer === pinchGestureRecognizer {
                if let pinchClaimDecision {
                    let decisionTouchIsActive = pinchDecisionTouch.map {
                        $0.phase != .ended && $0.phase != .cancelled
                    } ?? false
                    if pinchGestureRecognizer.numberOfTouches > 0 || decisionTouchIsActive {
                        return pinchClaimDecision
                    }
                    resetPinchClaimDecision()
                }
                guard pinchGestureRecognizer.numberOfTouches == 0,
                      let canvasView = installedCanvas,
                      let location = contentLocation(of: touch, in: canvasView) else {
                    return false
                }
                let shouldClaim = controller.selection != nil
                    && controller.selectionBounds?.contains(location) == true
                pinchClaimDecision = shouldClaim
                pinchDecisionTouch = touch
                return shouldClaim
            }

            guard gestureRecognizer === panGestureRecognizer else { return true }

            dragStartLocation = nil
            claimedDragIntent = nil
            guard let canvasView = installedCanvas,
                  let location = contentLocation(of: touch, in: canvasView) else { return false }
            let pointer: CapturePointerKind = touch.type == .pencil ? .pencil : .finger
            let allowsFingerCapture: Bool
#if targetEnvironment(simulator)
            #if DEBUG
            allowsFingerCapture = !ProcessInfo.processInfo.arguments.contains(
                "-vellum-force-pencil-only"
            )
            #else
            allowsFingerCapture = true
            #endif
#else
            allowsFingerCapture = false
#endif
            guard let intent = SelectionCapturePolicy.dragIntent(
                pointer: pointer,
                hasSelection: controller.selection != nil,
                allowsFingerCapture: allowsFingerCapture
            ) else { return false }

            dragStartLocation = location
            claimedDragIntent = intent
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let isCaptureGesture = gestureRecognizer === panGestureRecognizer
                || gestureRecognizer === pinchGestureRecognizer
            guard isCaptureGesture, let installedCanvas else {
                return false
            }
            if otherGestureRecognizer === installedCanvas.panGestureRecognizer {
                return true
            }
            if let canvasPinchGestureRecognizer = installedCanvas.pinchGestureRecognizer,
               otherGestureRecognizer === canvasPinchGestureRecognizer {
                return true
            }
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            (gestureRecognizer === panGestureRecognizer
                && otherGestureRecognizer === pinchGestureRecognizer)
                || (gestureRecognizer === pinchGestureRecognizer
                    && otherGestureRecognizer === panGestureRecognizer)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                guard let dragStartLocation, let claimedDragIntent else { return }
                activeDragIntent = claimedDragIntent
                switch claimedDragIntent {
                case .move:
                    controller.beginMoveDrag()
                    // A pan only begins once the touch has already travelled, and the drag may
                    // end without ever reporting a change, so carry that first leg over now.
                    updateMoveTranslation(for: gesture)
                case .capture:
                    controller.beginCapture(at: dragStartLocation, mode: selectionMode)
                    if let canvasView = gesture.view as? PKCanvasView,
                       let location = contentLocation(of: gesture, in: canvasView) {
                        controller.extendCapture(to: location)
                    }
                }
            case .changed:
                guard let canvasView = gesture.view as? PKCanvasView else { return }
                switch activeDragIntent {
                case .move:
                    updateMoveTranslation(for: gesture)
                    updateAutoScroll(for: gesture, in: canvasView)
                case .capture:
                    guard let location = contentLocation(of: gesture, in: canvasView)
                    else { return }
                    controller.extendCapture(to: location)
                case nil:
                    break
                }
            case .ended, .cancelled, .failed:
                switch activeDragIntent {
                case .move:
                    controller.endMoveDrag()
                case .capture:
                    controller.endCapture()
                case nil:
                    break
                }
                invalidateAutoScroll(clearDragLocation: true)
                activeDragIntent = nil
                claimedDragIntent = nil
                dragStartLocation = nil
            default:
                break
            }
        }

        private func updateMoveTranslation(for gesture: UIPanGestureRecognizer) {
            guard let canvasView = gesture.view as? PKCanvasView,
                  let dragStartLocation,
                  let location = contentLocation(of: gesture, in: canvasView) else { return }
            controller.setDragTranslation(
                CGSize(
                    width: location.x - dragStartLocation.x,
                    height: location.y - dragStartLocation.y
                )
            )
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                if activeDragIntent == .move {
                    invalidateAutoScroll(clearDragLocation: true)
                    panGestureRecognizer.isEnabled = false
                    panGestureRecognizer.isEnabled = true
                }
                controller.beginHandleDrag()
            case .changed:
                controller.setHandleTransform(
                    scale: CGSize(width: gesture.scale, height: gesture.scale),
                    rotation: 0
                )
            case .ended, .cancelled, .failed:
                controller.endHandleDrag()
                resetPinchClaimDecision()
            default:
                break
            }
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let canvasView = gesture.view as? PKCanvasView,
                  controller.selection != nil,
                  let bounds = controller.selectionBounds,
                  let location = contentLocation(of: gesture, in: canvasView),
                  !bounds.contains(location) else { return }
            controller.clearSelection()
        }

        private func contentLocation(
            of touch: UITouch,
            in canvasView: PKCanvasView
        ) -> CGPoint? {
            guard canvasView.zoomScale > 0 else { return nil }
            let location = touch.location(in: canvasView)
            return CGPoint(
                x: location.x / canvasView.zoomScale,
                y: location.y / canvasView.zoomScale
            )
        }

        private func contentLocation(
            of gesture: UIGestureRecognizer,
            in canvasView: PKCanvasView
        ) -> CGPoint? {
            guard canvasView.zoomScale > 0 else { return nil }
            let location = gesture.location(in: canvasView)
            return CGPoint(
                x: location.x / canvasView.zoomScale,
                y: location.y / canvasView.zoomScale
            )
        }

        private func updateAutoScroll(
            for gesture: UIPanGestureRecognizer,
            in canvasView: PKCanvasView
        ) {
            guard let canvasSuperview = canvasView.superview else {
                invalidateAutoScroll(clearDragLocation: true)
                return
            }

            lastDragScreenLocation = gesture.location(in: canvasSuperview)
            let viewportY = gesture.location(in: canvasView).y - canvasView.contentOffset.y
            let velocity = DragAutoScroll.velocity(
                position: viewportY,
                viewportLength: canvasView.bounds.height
            )
            guard velocity != 0 else {
                invalidateAutoScroll(clearDragLocation: false)
                return
            }
            guard autoScrollDisplayLink == nil else { return }

            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(handleAutoScrollTick(_:))
            )
            displayLink.add(to: .main, forMode: .common)
            autoScrollDisplayLink = displayLink
        }

        @objc private func handleAutoScrollTick(_ link: CADisplayLink) {
            guard activeDragIntent == .move,
                  let canvasView = installedCanvas,
                  let canvasSuperview = canvasView.superview,
                  let lastDragScreenLocation,
                  let dragStartLocation else {
                invalidateAutoScroll(clearDragLocation: true)
                return
            }

            let inCanvas = canvasView.convert(lastDragScreenLocation, from: canvasSuperview)
            let viewportY = inCanvas.y - canvasView.contentOffset.y
            let velocity = DragAutoScroll.velocity(
                position: viewportY,
                viewportLength: canvasView.bounds.height
            )
            guard velocity != 0 else {
                invalidateAutoScroll(clearDragLocation: false)
                return
            }

            let duration = CGFloat(link.targetTimestamp - link.timestamp)
            guard duration > 0 else { return }
            let delta = velocity * duration
            let minimumOffsetY = -canvasView.adjustedContentInset.top
            let maximumOffsetY = max(
                canvasView.contentSize.height
                    - canvasView.bounds.height
                    + canvasView.adjustedContentInset.bottom,
                minimumOffsetY
            )
            var contentOffset = canvasView.contentOffset
            contentOffset.y = min(
                max(contentOffset.y + delta, minimumOffsetY),
                maximumOffsetY
            )
            canvasView.contentOffset = contentOffset

            guard canvasView.zoomScale > 0 else {
                invalidateAutoScroll(clearDragLocation: true)
                return
            }
            let updatedInCanvas = canvasView.convert(
                lastDragScreenLocation,
                from: canvasSuperview
            )
            let contentLocation = CGPoint(
                x: updatedInCanvas.x / canvasView.zoomScale,
                y: updatedInCanvas.y / canvasView.zoomScale
            )
            controller.setDragTranslation(
                CGSize(
                    width: contentLocation.x - dragStartLocation.x,
                    height: contentLocation.y - dragStartLocation.y
                )
            )
        }

        private func invalidateAutoScroll(clearDragLocation: Bool) {
            autoScrollDisplayLink?.invalidate()
            autoScrollDisplayLink = nil
            if clearDragLocation {
                lastDragScreenLocation = nil
            }
        }

        private func resetPinchClaimDecision() {
            pinchClaimDecision = nil
            pinchDecisionTouch = nil
        }
    }
}
