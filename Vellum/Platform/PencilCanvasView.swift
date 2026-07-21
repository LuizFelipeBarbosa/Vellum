import Foundation
import PencilKit
import SwiftUI

struct CanvasViewport: Equatable, Sendable {
    var contentOffset: CGPoint
    var zoomScale: CGFloat
}

enum PencilSqueezePhase: Sendable {
    case began
    case ended
}

@MainActor
struct PencilCanvasView: UIViewRepresentable {
    let drawingData: Data?
    let onDrawingChanged: (Data) -> Void
    var isTransparent: Bool = false
    var tool: (any PKTool)? = nil
    var showsSystemToolPicker: Bool = true
    var onCanvasReady: ((PKCanvasView) -> Void)? = nil
    var isDrawingEnabled: Bool = true
    var onViewportChanged: ((CanvasViewport) -> Void)? = nil
    var onExternalDrawingChange: (() -> Void)? = nil
    var onPencilSqueeze: ((PencilSqueezePhase) -> Void)? = nil
    var onTwoFingerTap: (() -> Void)? = nil
    var onThreeFingerTap: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(
            onDrawingChanged: onDrawingChanged,
            onViewportChanged: onViewportChanged
        )
        coordinator.onExternalDrawingChange = onExternalDrawingChange
        coordinator.onPencilSqueeze = onPencilSqueeze
        coordinator.onTwoFingerTap = onTwoFingerTap
        coordinator.onThreeFingerTap = onThreeFingerTap
        return coordinator
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = isTransparent ? .clear : .white
        canvasView.isOpaque = !isTransparent
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 3
        canvasView.bouncesZoom = true
        canvasView.drawingGestureRecognizer.isEnabled = isDrawingEnabled

        let undoTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerTap(_:))
        )
        undoTap.numberOfTapsRequired = 1
        undoTap.numberOfTouchesRequired = 2
        undoTap.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        undoTap.delegate = context.coordinator

        let redoTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleThreeFingerTap(_:))
        )
        redoTap.numberOfTapsRequired = 1
        redoTap.numberOfTouchesRequired = 3
        redoTap.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        redoTap.delegate = context.coordinator

        undoTap.require(toFail: redoTap)
        canvasView.addGestureRecognizer(undoTap)
        canvasView.addGestureRecognizer(redoTap)

        if #available(iOS 17.5, *) {
            canvasView.addInteraction(UIPencilInteraction(delegate: context.coordinator))
        }

        if let tool {
            canvasView.tool = tool
        }

        if showsSystemToolPicker {
            context.coordinator.toolPicker.addObserver(canvasView)
            context.coordinator.isObservingToolPicker = true
            context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }

        onCanvasReady?(canvasView)
        context.coordinator.onViewportChanged?(
            CanvasViewport(
                contentOffset: canvasView.contentOffset,
                zoomScale: canvasView.zoomScale
            )
        )

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onViewportChanged = onViewportChanged
        context.coordinator.onExternalDrawingChange = onExternalDrawingChange
        context.coordinator.onPencilSqueeze = onPencilSqueeze
        context.coordinator.onTwoFingerTap = onTwoFingerTap
        context.coordinator.onThreeFingerTap = onThreeFingerTap
        canvasView.backgroundColor = isTransparent ? .clear : .white
        canvasView.isOpaque = !isTransparent
        canvasView.drawingGestureRecognizer.isEnabled = isDrawingEnabled

        if let tool, !Self.toolsMatch(canvasView.tool, tool) {
            canvasView.tool = tool
        }

        let beganObservingToolPicker: Bool
        if showsSystemToolPicker {
            if !context.coordinator.isObservingToolPicker {
                context.coordinator.toolPicker.addObserver(canvasView)
                context.coordinator.isObservingToolPicker = true
                context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
                canvasView.becomeFirstResponder()
                beganObservingToolPicker = true
            } else {
                beganObservingToolPicker = false
            }
        } else if context.coordinator.isObservingToolPicker {
            context.coordinator.toolPicker.setVisible(false, forFirstResponder: canvasView)
            context.coordinator.toolPicker.removeObserver(canvasView)
            context.coordinator.isObservingToolPicker = false
            beganObservingToolPicker = false
        } else {
            beganObservingToolPicker = false
        }

        guard !context.coordinator.hasTransientDrawingOverride,
              let drawingData,
              drawingData != canvasView.drawing.dataRepresentation(),
              let drawing = try? PKDrawing(data: drawingData) else {
            return
        }

        context.coordinator.isUpdatingFromModel = true
        canvasView.drawing = drawing
        context.coordinator.isUpdatingFromModel = false
        context.coordinator.onExternalDrawingChange?()

        if showsSystemToolPicker,
           !beganObservingToolPicker,
           canvasView.window != nil,
           !canvasView.isFirstResponder {
            context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }
    }

    static func dismantleUIView(_ canvasView: PKCanvasView, coordinator: Coordinator) {
        if coordinator.isObservingToolPicker {
            coordinator.toolPicker.removeObserver(canvasView)
        }
    }

    private static func toolsMatch(_ lhs: any PKTool, _ rhs: any PKTool) -> Bool {
        if let lhs = lhs as? PKInkingTool, let rhs = rhs as? PKInkingTool {
            return lhs == rhs
        }
        if let lhs = lhs as? PKEraserTool, let rhs = rhs as? PKEraserTool {
            return lhs == rhs
        }
        if let lhs = lhs as? PKLassoTool, let rhs = rhs as? PKLassoTool {
            return lhs == rhs
        }
        return false
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate,
        UIGestureRecognizerDelegate {
        let toolPicker = PKToolPicker()
        var onDrawingChanged: (Data) -> Void
        var onViewportChanged: ((CanvasViewport) -> Void)?
        var isProgrammaticChange = false
        private(set) var suppressedChangeOccurred = false
        var onExternalDrawingChange: (() -> Void)?
        var onPencilSqueeze: ((PencilSqueezePhase) -> Void)?
        var onTwoFingerTap: (() -> Void)?
        var onThreeFingerTap: (() -> Void)?
        var isUpdatingFromModel = false
        var isObservingToolPicker = false
        /// True while the selection controller has intentionally diverged canvasView.drawing
        /// from the model (strokes hidden during a drag); updateUIView must not re-sync
        /// the canvas from drawingData while set.
        var hasTransientDrawingOverride = false

        init(
            onDrawingChanged: @escaping (Data) -> Void,
            onViewportChanged: ((CanvasViewport) -> Void)?
        ) {
            self.onDrawingChanged = onDrawingChanged
            self.onViewportChanged = onViewportChanged
        }

        func beginProgrammaticChange() {
            isProgrammaticChange = true
            suppressedChangeOccurred = false
        }

        func endProgrammaticChange(_ canvasView: PKCanvasView) {
            isProgrammaticChange = false
            if suppressedChangeOccurred {
                onDrawingChanged(canvasView.drawing.dataRepresentation())
            }
        }

        func performSilentChange(_ body: () -> Void) {
            let wasProgrammaticChange = isProgrammaticChange
            let hadSuppressedChange = suppressedChangeOccurred
            isProgrammaticChange = true
            body()
            isProgrammaticChange = wasProgrammaticChange
            suppressedChangeOccurred = hadSuppressedChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingFromModel else { return }
            if isProgrammaticChange {
                suppressedChangeOccurred = true
                return
            }
            onDrawingChanged(canvasView.drawing.dataRepresentation())
            onExternalDrawingChange?()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportViewport(for: scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            reportViewport(for: scrollView)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onTwoFingerTap?()
        }

        @objc func handleThreeFingerTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onThreeFingerTap?()
        }

        @available(iOS 17.5, *)
        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
            guard UIPencilInteraction.preferredSqueezeAction != .ignore else { return }
            switch squeeze.phase {
            case .began: onPencilSqueeze?(.began)
            case .changed: break
            case .ended, .cancelled: onPencilSqueeze?(.ended)
            @unknown default: onPencilSqueeze?(.ended)
            }
        }

        private func reportViewport(for scrollView: UIScrollView) {
            onViewportChanged?(
                CanvasViewport(
                    contentOffset: scrollView.contentOffset,
                    zoomScale: scrollView.zoomScale
                )
            )
        }
    }
}
